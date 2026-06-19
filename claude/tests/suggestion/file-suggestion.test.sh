#!/usr/bin/env bash
# Hermetic unit tests for ~/.claude/suggestion/file-suggestion.sh
#
# Builds a throwaway fixture (a fake workspace `corecs` + a fake extra root
# `vault`, both git repos) in a temp dir, drives the helper over stdin, and
# asserts on stdout. Nothing here touches the live vault. Run: bash this-file.

set -u
SCRIPT="${FILE_SUGGESTION_SCRIPT:-$HOME/.claude/suggestion/file-suggestion.sh}"

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }

# run "<query>" -> sets $OUT and $RC
run() {
  OUT=$(printf '{"query":%s,"cwd":%s}' "$(jq -Rn --arg q "$1" '$q')" "$(jq -Rn --arg c "$CWD" '$c')" \
        | FILE_SUGGESTION_EXTRA_ROOTS="$VAULT" FILE_SUGGESTION_MAX="${MAX:-50}" bash "$SCRIPT")
  RC=$?
}

has()    { case "$OUT" in *"$1"*) ok "$2";; *) bad "$2" "expected to contain: $1";; esac; }
hasnt()  { case "$OUT" in *"$1"*) bad "$2" "expected NOT to contain: $1";; *) ok "$2";; esac; }
rc_is()  { [ "$RC" -eq "$1" ] && ok "$2" || bad "$2" "exit $RC != $1"; }
lines()  { printf '%s\n' "$OUT" | grep -c . ; }

# ---- fixture ------------------------------------------------------------
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CWD="$TMP/corecs"
VAULT="$TMP/vault"

mkfile() { mkdir -p "$(dirname "$1")"; : >"$1"; }
gitinit() { git -C "$1" init -q; }

mkdir -p "$CWD" "$VAULT"
# workspace
mkfile "$CWD/CLAUDE.md"
mkfile "$CWD/src/app.js"
mkfile "$CWD/src/util.js"
mkfile "$CWD/notes/corecs-note.md"
mkfile "$CWD/build/generated.js"        # will be gitignored
printf 'build/\n' >"$CWD/.gitignore"
gitinit "$CWD"
# extra root ("vault")
mkfile "$VAULT/meta/docs/agent-conduct.md"
mkfile "$VAULT/projects/mnhi/bootstrap.md"
mkfile "$VAULT/projects/mnhi/decisions/foo/decision-one.md"
mkfile "$VAULT/projects/mnhi/decisions/bar/decision-two.md"
mkfile "$VAULT/projects/corecs/readme.md"
gitinit "$VAULT"

# ---- tests --------------------------------------------------------------
echo "file-suggestion.sh"

run "mnhi"
has  "$VAULT/projects/mnhi/bootstrap.md" "bare query searches extra roots (@mnhi)"
rc_is 0 "exit 0 on match"

run "agent"
has  "$VAULT/meta/docs/agent-conduct.md" "bare fuzzy word hits extra root"

run "app"
has  "$CWD/src/app.js" "bare query searches cwd"

run "corecs"
has  "$CWD/notes/corecs-note.md"       "@corecs hits the workspace tree"
has  "$VAULT/projects/corecs/readme.md" "@corecs ALSO hits vault/projects/corecs (interleave keeps both)"

run "mnhi/decision"
has  "$VAULT/projects/mnhi/decisions/foo/decision-one.md" "fuzzy drill across dirs (mnhi/decision)"
hasnt "bootstrap.md" "drill excludes non-matching siblings"

# tab-completed absolute path, then more typing, keeps matching
run "$VAULT/projects/mnhi/dec"
has  "$VAULT/projects/mnhi/decisions/foo/decision-one.md" "absolute query keeps matching after tab-complete"

run ""
has  "$CWD/CLAUDE.md" "empty query lists cwd"
has  "$VAULT/projects/mnhi/bootstrap.md" "empty query lists extra roots too"

run "definitely-no-such-thing-xyz"
[ -z "$OUT" ] && ok "no-match yields empty output" || bad "no-match yields empty output" "got: $OUT"
rc_is 0 "exit 0 even with no matches"

run 'a.b(c[d'
rc_is 0 "regex-special query does not crash"

# gitignore is respected
run "generated"
hasnt "build/generated.js" "gitignored files excluded"

# dedup when a path would appear twice (vault listed as its own extra root twice)
OUT=$(printf '{"query":"corecs","cwd":%s}' "$(jq -Rn --arg c "$CWD" '$c')" \
      | FILE_SUGGESTION_EXTRA_ROOTS="$VAULT $VAULT" bash "$SCRIPT")
dups=$(printf '%s\n' "$OUT" | sort | uniq -d | grep -c . )
[ "$dups" -eq 0 ] && ok "duplicate roots are de-duplicated" || bad "duplicate roots are de-duplicated" "$dups dup lines"

# cap is enforced — empty query matches all ~10 fixture files, so MAX=3 must clamp
MAX=3 run ""
n=$(lines)
[ "$n" -eq 3 ] && ok "MAX cap clamps (10 candidates -> exactly 3)" || bad "MAX cap clamps" "got $n lines, expected 3"
unset MAX

# ---- summary ------------------------------------------------------------
echo
printf 'passed %d, failed %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
