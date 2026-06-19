#!/usr/bin/env python3
"""Recovery-cost preview: how expensive is it to 'inherit' a handoff/note?

Reads a root markdown doc, follows its links (wikilinks, markdown links, and
frontmatter related/epic/parent/domain/supersedes refs), recurses, and reports
the token cost of pulling the whole graph into context.

Use it two ways:
  - at CREATION: if the root + its links balloon, break things out / prune links.
  - at LOADING:  decide how deep to actually read (the tree shows where cost is).

Cost model: loading a doc = its tokens become input, cache-written once at the
1h rate (×2), then re-read ×0.1/turn. We report raw tokens and the one-time
"load TEq" (tokens×2). Token counts are char/4 estimates.

Usage:
  vault-cost.py <root.md> [--vault DIR] [--depth N]
"""
import sys, os, re, glob

TPC = 0.25  # tokens per char
WIKILINK = re.compile(r"\[\[([^\]]+)\]\]")
MDLINK   = re.compile(r"(?<!\!)\[[^\]]*\]\(([^)]+)\)")
FM_PATH  = re.compile(r"([^\s\"'\[\]]+\.md)")

def toks(s): return int(len(s) * TPC)

def split_fm(text):
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            return text[3:end], text[end+4:]
    return "", text

def extract_links(text):
    """Return a list of raw link targets (wikilink names, md paths, fm paths)."""
    fm, body = split_fm(text)
    out = []
    for m in WIKILINK.finditer(text):
        out.append(("wiki", m.group(1).split("|")[0].split("#")[0].strip()))
    for m in MDLINK.finditer(text):
        p = m.group(1).strip()
        if not p.startswith(("http://", "https://", "#", "mailto:")):
            out.append(("path", p.split("#")[0]))
    for m in FM_PATH.finditer(fm):                      # bare paths in frontmatter
        out.append(("path", m.group(1)))
    # de-dup preserving order
    seen=set(); uniq=[]
    for t in out:
        if t[1] and t not in seen: seen.add(t); uniq.append(t)
    return uniq

def resolve(kind, target, doc_dir, vault):
    cands = []
    if kind == "path" or "/" in target or target.endswith(".md"):
        base = target if target.endswith(".md") else target + ".md"
        cands += [os.path.normpath(os.path.join(doc_dir, base)),
                  os.path.normpath(os.path.join(vault, base.lstrip("/")))]
    if "/" not in target:                               # bare wikilink name → search vault
        name = target[:-3] if target.endswith(".md") else target
        hits = glob.glob(os.path.join(vault, "**", name + ".md"), recursive=True)
        if not hits:                                    # fuzzy: -/_ swap (our files differ)
            alt = name.replace("-", "_");
            hits = glob.glob(os.path.join(vault, "**", alt + ".md"), recursive=True) or \
                   glob.glob(os.path.join(vault, "**", name.replace("_","-") + ".md"), recursive=True)
        cands += hits
    for c in cands:
        if os.path.isfile(c): return c
    return None

def main():
    root = os.path.abspath(sys.argv[1])
    vault = os.path.abspath(sys.argv[sys.argv.index("--vault")+1]) if "--vault" in sys.argv else os.path.dirname(root)
    max_depth = int(sys.argv[sys.argv.index("--depth")+1]) if "--depth" in sys.argv else 99

    visited = {}              # path -> tokens
    dead = []                 # (target, referenced_by)
    by_depth = {}             # depth -> [tokens]
    lines = []

    def walk(path, depth, prefix, is_last):
        if depth > max_depth: return
        rel = os.path.relpath(path, vault)
        connector = "" if depth == 0 else ("└─ " if is_last else "├─ ")
        if path in visited:
            lines.append(f"{prefix}{connector}{rel}  ↩ (already counted)")
            return
        try: text = open(path, errors="ignore").read()
        except OSError:
            lines.append(f"{prefix}{connector}{rel}  [unreadable]"); return
        t = toks(text); visited[path] = t
        by_depth.setdefault(depth, []).append(t)
        lines.append(f"{prefix}{connector}{rel}  {t:,} tok")
        links = extract_links(text)
        kids = []
        for kind, tgt in links:
            r = resolve(kind, tgt, os.path.dirname(path), vault)
            if r and os.path.abspath(r) != path: kids.append(r)
            elif not r: dead.append((tgt, rel))
        child_prefix = prefix + ("" if depth == 0 else ("   " if is_last else "│  "))
        for i, k in enumerate(kids):
            walk(os.path.abspath(k), depth+1, child_prefix, i == len(kids)-1)

    walk(root, 0, "", True)
    total = sum(visited.values())
    print("\n".join(lines))
    print(f"\ndocs reached     : {len(visited)}")
    print(f"total tokens     : {total:,}   (one-time load ≈ {total*2:,} TEq, then {int(total*0.1):,}/turn to carry)")
    print("cost by depth    :")
    cum = 0
    for d in sorted(by_depth):
        s = sum(by_depth[d]); cum += s
        print(f"  depth {d}: {len(by_depth[d]):>2} docs  {s:>7,} tok   (cumulative {cum:,})")
    if dead:
        print(f"\ndead/unresolved links ({len(dead)}) — broken refs or things to create:")
        for tgt, src in dead[:20]:
            print(f"  '{tgt}'  ← referenced by {src}")

if __name__ == "__main__":
    if len(sys.argv) < 2: print(__doc__); sys.exit(1)
    main()
