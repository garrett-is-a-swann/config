#!/usr/bin/env python3
"""Per-source context-residency cost for a Claude Code session.

Once content enters context (a Read result, an Edit/Write's args, a Bash
command's output, ...) it is RE-READ on every API call afterwards at 0.1x,
until a /compact evicts it. So something added long ago keeps costing
`size x calls_since x 0.1`, growing invisibly.

Buckets EVERY tool interaction:
  - file tools (Read/Edit/Write/NotebookEdit) -> by file path
  - Bash                                       -> by command head (Bash:python3)
  - everything else (Grep/Glob/WebFetch/Task)  -> by tool name

Columns:
  inter    interactions that put content in context
  resident tokens this source currently contributes to the prefix (~char/4)
  rereads  re-read token-equivalents spent on it SO FAR (sunk cost)
  %re-rd   share of the session's total re-read TEq
  per-call what each FUTURE turn keeps paying to keep it resident (resident*0.1)
  stale    API calls since you last touched it (high stale+per-call = evict)

Denominators are printed up top so you can see how much this actually matters.
Token counts are char/4 approximations; a big cache_read drop = assumed /compact.

Usage: cache-files.py [transcript.jsonl]   (defaults to current session)
"""
import json, glob, os, sys

def hn(n):
    n=float(n)
    return f"{n/1e6:.2f}M" if n>=1e6 else f"{n/1e3:.0f}k" if n>=1e3 else f"{n:.0f}"

def toks(x):
    return len(x if isinstance(x,str) else json.dumps(x))/4

FILE_TOOLS={"Read","Edit","MultiEdit","Write","NotebookEdit"}

def bucket_key(name, inp):
    fp = inp.get("file_path") or inp.get("path") or inp.get("notebook_path")
    if name in FILE_TOOLS and fp: return fp, True
    if name=="Bash":
        cmd=(inp.get("command","") or "").strip().split()
        head=os.path.basename(cmd[0]) if cmd else "?"
        return f"Bash:{head}", False
    return name or "?", False

def analyze(path):
    meta={}                      # tool_use_id -> (name, key, is_file, input_tokens)
    buckets={}                   # key -> {tok,count,last,entries,is_file}
    calls=0; running_max=0; resets=0
    read_teq=write_teq=out_teq=in_teq=0.0
    seen_msg=set(); seen_tu=set(); seen_tr=set()   # billing / tool-use / tool-result dedup

    def rec(key, is_file):
        return buckets.setdefault(key, {"tok":0,"count":0,"last":0,"entries":[],"is_file":is_file})

    for line in open(path, errors="ignore"):
        line=line.strip()
        if not line: continue
        try: d=json.loads(line)
        except Exception: continue
        m=d.get("message") or {}
        content=m.get("content"); u=m.get("usage") or {}
        # --- billing: count each API call once, by message.id ---
        if "cache_read_input_tokens" in u or "cache_creation_input_tokens" in u:
            mid=m.get("id")
            if not (mid and mid in seen_msg):
                if mid: seen_msg.add(mid)
                rd=u.get("cache_read_input_tokens",0) or 0
                if running_max>20000 and rd < 0.55*running_max:
                    buckets.clear(); resets+=1
                running_max=max(running_max, rd)
                calls+=1
                read_teq  += rd*0.1
                write_teq += (u.get("cache_creation_input_tokens",0) or 0)*2
                out_teq   += (u.get("output_tokens",0) or 0)*5
                in_teq    += (u.get("input_tokens",0) or 0)*1
        # --- tool blocks: dedup independently (one turn can hold many calls) ---
        if isinstance(content, list):
            for b in content:
                if not isinstance(b,dict): continue
                if b.get("type")=="tool_use":
                    tid=b.get("id")
                    if tid in seen_tu: continue
                    seen_tu.add(tid)
                    name=b.get("name",""); inp=b.get("input",{}) or {}
                    key,is_file=bucket_key(name, inp)
                    meta[tid]=(name, key, is_file, toks(inp))
                elif b.get("type")=="tool_result":
                    tid=b.get("tool_use_id")
                    if tid in seen_tr: continue
                    seen_tr.add(tid)
                    mt=meta.get(tid)
                    if not mt: continue
                    name,key,is_file,in_tok=mt
                    c=b.get("content","")
                    t=in_tok+toks(c)
                    r=rec(key,is_file); r["tok"]+=t; r["count"]+=1; r["last"]=calls
                    r["entries"].append((t,calls))

    total=calls
    sess_teq=read_teq+write_teq+out_teq+in_teq or 1
    rows=[]
    for key,r in buckets.items():
        rr=sum(t*(total-c)*0.1 for t,c in r["entries"])
        rows.append((rr, key, r, r["tok"]*0.1, total-r["last"]))
    rows.sort(reverse=True)
    attributed=sum(x[0] for x in rows)

    print(f"# {os.path.basename(path)}  |  {total} API calls" + (f"  |  {resets} compaction(s)" if resets else ""))
    print(f"# session usage: {hn(sess_teq)} TEq total   |   re-reads {hn(read_teq)} ({read_teq/sess_teq*100:.0f}% of usage)")
    print(f"# this report attributes {hn(attributed)} of the {hn(read_teq)} re-read TEq ({attributed/max(read_teq,1)*100:.0f}%); the rest is conversation/system/thinking\n")
    print(f"{'source':<34}{'inter':>9}{'resident':>10}{'rereads':>9}{'%re-rd':>7}{'per-call':>9}{'stale':>7}")
    for rr,key,r,per_call,stale in rows:
        inter=f"{r['count']}x"
        name=key if len(key)<=33 else "…"+key[-32:]
        print(f"{name:<34}{inter:>9}{hn(r['tok']):>10}{hn(rr):>9}{rr/max(read_teq,1)*100:>6.1f}%{hn(per_call):>9}{str(stale)+'c':>7}")
    print(f"{'─ attributed (files+tools)':<34}{'':>9}{'':>10}{hn(attributed):>9}{attributed/max(read_teq,1)*100:>6.1f}%")
    print(f"{'─ remainder (conversation/system/think)':<34}{'':>9}{'':>10}{hn(max(0,read_teq-attributed)):>9}{max(0,read_teq-attributed)/max(read_teq,1)*100:>6.1f}%")
    eh=[(key,per_call,stale) for rr,key,r,per_call,stale in rows if per_call>1000 and stale>=5]
    if eh:
        print("\nEVICTION CANDIDATES (costly + not touched recently) — /compact reclaims these:")
        for key,per_call,stale in eh[:8]:
            print(f"  {hn(per_call)}/call ongoing, idle {stale} calls  →  {key}")

f = sys.argv[1] if len(sys.argv)>1 else sorted(
    glob.glob(os.path.expanduser("~/.claude/projects/-workspace/*.jsonl")), key=os.path.getmtime)[-1]
analyze(f)
