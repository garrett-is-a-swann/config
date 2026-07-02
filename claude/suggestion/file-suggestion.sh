#!/usr/bin/env bash
# Claude Code @-mention file-suggestion helper.
#
# Contract (reverse-engineered from the CC 2.1.x binary, fn xzq/Gp8):
#   stdin : JSON { "query": "<text typed after @>", "cwd": "<workspace>", ... }
#   stdout: newline-separated paths; each line becomes a suggestion whose
#           displayText IS the inserted text (no rewriting, no existence check).
#   exit  : must be 0, else CC discards all output.
#
# Model: a UNIFIED fuzzy finder over the workspace cwd plus EXTRA_ROOTS. The
# query is split on `/` and whitespace into an ordered `.*` regex and matched
# against each candidate's ABSOLUTE path; suggestions are emitted as absolute
# paths. Consequences (all intended):
#   - `@mnhi`         matches anywhere under any root (bare, no prefix needed)
#   - `@corecs`       matches /home/node/corecs/** AND /home/node/vault/projects/corecs/**
#   - tab-complete to /home/node/vault/ then keep typing -> still matches, because
#     the now-absolute query is matched against absolute candidates
# Results per root are interleaved so every root stays represented under the cap.
#
# Listing uses `git ls-files` (gitignore-aware) with a `find` fallback. NB: `rg`
# here is only a shell function (-> grep), absent in this non-interactive shell.
# No `set -e`/`pipefail`: an empty grep returns 1, which would zero the output.

# Roots searched in addition to the workspace cwd. Override for testing via
# FILE_SUGGESTION_EXTRA_ROOTS (space-separated) and FILE_SUGGESTION_MAX.
if [ -n "${FILE_SUGGESTION_EXTRA_ROOTS:-}" ]; then
    read -r -a EXTRA_ROOTS <<<"$FILE_SUGGESTION_EXTRA_ROOTS"
else
    EXTRA_ROOTS=(/home/node/vault)
fi
MAX=${FILE_SUGGESTION_MAX:-50}

payload=$(cat)
query=$(jq -r '.query // ""' <<<"$payload" 2>/dev/null)
cwd=$(jq -r '.cwd // "."' <<<"$payload" 2>/dev/null)

# absolute paths of files under $1
list_abs() {
    if git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$1" ls-files --cached --others --exclude-standard 2>/dev/null | sed "s#^#$1/#"
        # Check others for nested git directories, and include those in the search.
        git -C "$1" ls-files --others --directory 2>/dev/null | sed 's#/$##' |
            while IFS= read -r sub; do
                [ -n "$sub" ] && [ -e "$1/$sub/.git" ] && list_abs "$1/$sub"
            done
    else
        find "$1" -type f 2>/dev/null
    fi
}

# query -> loose case-insensitive ERE: regex-specials escaped, then runs of
# `/` or space become `.*` so "vault/mnhi/decision" drills fuzzily.
to_pat() { printf '%s' "$1" | sed -e 's/[][(){}.^$*+?|\\]/\\&/g' -e 's#[/ ]\{1,\}#.*#g'; }

filt() { if [ -n "$query" ]; then grep -iE -- "$(to_pat "$query")"; else cat; fi; }

# Build the root list (cwd first, then existing extra roots), emit each root's
# filtered+capped results tagged with (rank, root_index), then sort by rank so
# the roots interleave round-robin, dedup, and cap.
roots=("$cwd")
for r in "${EXTRA_ROOTS[@]}"; do [ -d "$r" ] && roots+=("$r"); done

i=0
for s in "${roots[@]}"; do
    list_abs "$s" 2>/dev/null | filt | head -n "$MAX" | awk -v r="$i" '{printf "%d\t%d\t%s\n", NR, r, $0}'
    i=$((i + 1))
done 2>/dev/null |
    sort -k1,1n -k2,2n -s |
    cut -f3- |
    awk '!seen[$0]++' |
    head -n "$MAX"

exit 0
