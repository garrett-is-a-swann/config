#!/usr/bin/env python3
"""Per-session prompt-cache stats for the statusline HUD.

Emits:  <misses> <good_read_tokens> <wasted_tokens> <last_miss> <last_read>
  misses    = turn-openers that re-wrote the bulk of a previously-warm prefix
              (create>read AND create>half the prior warm prefix). TTL-agnostic:
              works whether the cache TTL is 5min or 1h.
  good      = cumulative cache-READ tokens (served warm at 0.1x)
  wasted    = prefix tokens needlessly re-written by those misses
  last_miss = 1 if the most recent turn opened on a miss, else 0
  last_read = cache-read tokens of the most recent record (current warm prefix)

A "turn-opener" is the first assistant API call after a genuine user message
(role=user, not a tool_result), so within-turn tool calls don't get miscounted.
Memoized on transcript file size so idle statusline renders are ~free.
"""
import sys, os, json, hashlib

def is_real_user(d):
    m = d.get("message") or {}
    if m.get("role") != "user":
        return False
    c = m.get("content")
    if isinstance(c, str):
        return True
    if isinstance(c, list):
        return not any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c)
    return False

if len(sys.argv) < 2:
    print("0 0 0 0 0"); sys.exit()
path = sys.argv[1]
try:
    sig = str(os.stat(path).st_size)
except OSError:
    print("0 0 0 0 0"); sys.exit()

memo_dir = os.path.expanduser("~/.claude/.statusline-cache")
os.makedirs(memo_dir, exist_ok=True)
memo = os.path.join(memo_dir, hashlib.md5(path.encode()).hexdigest() + ".memo")
if os.path.exists(memo):
    try:
        c = open(memo).read().split()
        if len(c) == 6 and c[0] == sig:
            print(" ".join(c[1:])); sys.exit()
    except Exception:
        pass

misses = good = waste = 0
last_miss = 0
last_read = 0
prev_warm = 0          # warm prefix size carried from the previous turn
pending_open = False   # next assistant usage record opens a new user turn

with open(path, errors="ignore") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        if is_real_user(d):
            pending_open = True
            continue
        u = (d.get("message") or {}).get("usage") or {}
        if "cache_read_input_tokens" not in u and "cache_creation_input_tokens" not in u:
            continue
        cr = u.get("cache_creation_input_tokens", 0) or 0
        rd = u.get("cache_read_input_tokens", 0) or 0
        good += rd
        last_read = rd
        if pending_open:
            # real miss = rewrote the bulk of what was warm last turn
            if cr > rd and prev_warm > 5000 and cr > 0.5 * prev_warm:
                misses += 1
                waste += min(cr, prev_warm)
                last_miss = 1
            else:
                last_miss = 0
            pending_open = False
        prev_warm = max(prev_warm, rd) if rd else prev_warm
        if rd:               # once we have a warm read, that's the live prefix
            prev_warm = rd

res = f"{misses} {good} {waste} {last_miss} {last_read}"
try:
    open(memo, "w").write(f"{sig} {res}")
except Exception:
    pass
print(res)
