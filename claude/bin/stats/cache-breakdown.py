#!/usr/bin/env python3
"""Usage breakdown for a Claude Code session (or a multi-day window).

Two linked views, because usage has two axes:

  A) BILLING view (exact) — every token billed, by API line, in token-equivalents
     (TEq = tokens x multiplier).  Multipliers: input x1, cache-read x0.1,
     cache-write x2 (1h TTL), output x5.  This is literally your usage burn.

  B) ORIGIN view (approx) — what *generated* those tokens, by content block:
     user text / agent text / tool calls / tool results / thinking.  Output is
     split by tokenizing the model's content blocks; context additions use a
     ~4 char/token estimate.  Tells you WHAT is filling context and re-reads.

Usage:
  cache-breakdown.py <transcript.jsonl>     # one session
  cache-breakdown.py --days 7               # all sessions, last 7 days
"""
import json, glob, os, sys, datetime as dt

MULT = {"input": 1.0, "read": 0.1, "write": 2.0, "output": 5.0}

def hn(n):
    n = float(n)
    return f"{n/1e6:.2f}M" if n >= 1e6 else f"{n/1e3:.0f}k" if n >= 1e3 else f"{n:.0f}"

def parse_ts(s):
    try: return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception: return None

def blocks_chars(content):
    """Return char counts per origin from a message content (list or str)."""
    out = {"user_text": 0, "agent_text": 0, "tool_call": 0, "tool_result": 0, "thinking": 0}
    if isinstance(content, str):
        out["user_text"] += len(content); return out
    if not isinstance(content, list):
        return out
    for b in content:
        if not isinstance(b, dict): continue
        t = b.get("type")
        if t == "text":      out["agent_text"]  += len(b.get("text", ""))
        elif t == "thinking":out["thinking"]    += len(b.get("thinking", ""))
        elif t == "tool_use":out["tool_call"]   += len(json.dumps(b.get("input", "")))+len(b.get("name",""))
        elif t == "tool_result":
            c = b.get("content", "")
            out["tool_result"] += len(c if isinstance(c, str) else json.dumps(c))
    return out

def run(files, since=None):
    bill = {"input":0, "read":0, "write":0, "output":0}
    origin = {"user_text":0, "agent_text":0, "tool_call":0, "tool_result":0, "thinking":0}  # ~char/4 tokens
    seen = set()
    for f in files:
        for line in open(f, errors="ignore"):
            line = line.strip()
            if not line: continue
            try: d = json.loads(line)
            except Exception: continue
            if since:
                ts = parse_ts(d.get("timestamp", ""))
                if ts and ts < since: continue
            m = d.get("message") or {}
            role = m.get("role")
            content = m.get("content")
            # origin (context additions), approx char/4
            ch = blocks_chars(content)
            # a user role with only a string is the human; user role with blocks = tool results
            if role == "user" and isinstance(content, str):
                origin["user_text"] += ch["user_text"] / 4
            else:
                for k in ("agent_text","tool_call","tool_result","thinking"):
                    origin[k] += ch[k] / 4
            # billing (exact) — only assistant records carry usage
            u = m.get("usage") or {}
            if "cache_read_input_tokens" not in u and "cache_creation_input_tokens" not in u:
                continue
            mid = m.get("id")
            if mid and mid in seen: continue
            if mid: seen.add(mid)
            bill["read"]   += u.get("cache_read_input_tokens", 0) or 0
            bill["write"]  += u.get("cache_creation_input_tokens", 0) or 0
            bill["output"] += u.get("output_tokens", 0) or 0
            bill["input"]  += u.get("input_tokens", 0) or 0

    teq = {k: bill[k]*MULT[{"input":"input","read":"read","write":"write","output":"output"}[k]] for k in bill}
    grand = sum(teq.values()) or 1

    # unified single-axis attribution (output split into thinking/tools/text)
    est_text = origin["agent_text"]; est_tool = origin["tool_call"]
    think_other = max(0, bill["output"] - est_text - est_tool)
    uni = [("Re-reads", teq["read"]), ("Writes", teq["write"]), ("Thinking", think_other*5),
           ("ToolCalls", est_tool*5), ("AgentText", est_text*5), ("Input", teq["input"])]
    print("SUMMARY  " + " | ".join(f"{n}:{v/grand*100:.0f}%" for n,v in uni))
    print(f"         (total usage this scope = {hn(grand)} token-equivalents)\n")

    print("=== A) BILLING — your actual usage (token-equivalents) ===")
    print(f"{'category':<14}{'tokens':>10}{'  mult':>7}{'   TEq':>10}{'  share':>8}")
    rows = [("Re-reads","read"),("Cache writes","write"),("Output","output"),("Fresh input","input")]
    for label,k in rows:
        print(f"{label:<14}{hn(bill[k]):>10}{('x'+str(MULT[k])):>7}{hn(teq[k]):>10}{teq[k]/grand*100:>7.1f}%")
    print(f"{'TOTAL':<14}{'':>10}{'':>7}{hn(grand):>10}{100.0:>7.1f}%")

    print("\n=== B) ORIGIN — what generated the cost ===")
    # Output bucket split: visible text + tool-call args (est. char/4); remainder
    # is thinking (stored redacted, but billed). Reconciles to A. (computed above)
    print("Output (x5) split by what the model produced (thinking = remainder):")
    for label,toks in [("  agent text",est_text),("  tool calls",est_tool),("  thinking",think_other)]:
        print(f"{label:<16}{hn(toks):>10}{'x5.0':>7}{hn(toks*5):>10}{toks*5/grand*100:>7.1f}% of total")
    print("\nContext composition (approx) — what fills context & drives re-reads:")
    otot = sum(origin.values()) or 1
    for label,k in [("  tool results","tool_result"),("  agent text","agent_text"),
                    ("  tool calls","tool_call"),("  thinking","thinking"),("  your text","user_text")]:
        print(f"{label:<14}{hn(origin[k]):>10}{origin[k]/otot*100:>7.1f}%")

since = None; files = []
if len(sys.argv) >= 3 and sys.argv[1] == "--days":
    days = float(sys.argv[2]); since = dt.datetime.now(dt.timezone.utc).timestamp() - days*86400
    files = glob.glob(os.path.expanduser("~/.claude/projects/**/*.jsonl"), recursive=True)
    print(f"# window: last {days:g} days, {len(files)} transcripts\n")
elif len(sys.argv) >= 2:
    files = [sys.argv[1]]
else:
    files = [sorted(glob.glob(os.path.expanduser("~/.claude/projects/-workspace/*.jsonl")), key=os.path.getmtime)[-1]]
    print(f"# current session\n")
run(files, since)
