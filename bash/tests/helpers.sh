# Minimal test harness + git fixtures for the PS1 ahead/behind tests.
# Sourced by each *.test.sh; the per-test state lives in globals reset by
# new_fixture. Tests assert with assert_eq / assert_empty; run.sh tallies.

TESTS_RUN=0
TESTS_FAILED=0

# Resolve the script under test relative to this helpers file.
__helpers_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_UNDER_TEST="$__helpers_dir/../git-ps1-ahead-behind.sh"

assert_eq() {
    # assert_eq <expected> <actual> <description>
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$1" = "$2" ]; then
        printf 'ok %d - %s\n' "$TESTS_RUN" "$3"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf 'not ok %d - %s\n' "$TESTS_RUN" "$3"
        printf '#   expected: %q\n#   actual:   %q\n' "$1" "$2"
    fi
}

assert_empty() {
    # assert_empty <actual> <description>
    assert_eq "" "$1" "$2"
}

# new_fixture [--with-upstream]
#
# Builds a throwaway working repo on branch `master` with a single pushed base
# commit, plus one or two bare remotes. Sets globals: FIXTURE, WORK, ORIGIN,
# UPSTREAM. Points XDG_CACHE_HOME at a clean per-fixture cache, then (re)sources
# the script under test so __ore_ps1_git_cache_dir tracks it. Throttles are set
# to 0 so each refresh recomputes; tests that exercise throttling override them.
new_fixture() {
    local with_upstream=""
    [ "${1:-}" = "--with-upstream" ] && with_upstream=1

    FIXTURE="$(mktemp -d)"
    ORIGIN="$FIXTURE/origin.git"
    UPSTREAM="$FIXTURE/upstream.git"
    WORK="$FIXTURE/work"

    git init -q --bare "$ORIGIN"
    [ -n "$with_upstream" ] && git init -q --bare "$UPSTREAM"

    git init -q "$WORK"
    git -C "$WORK" config user.email test@test
    git -C "$WORK" config user.name test
    git -C "$WORK" config commit.gpgsign false
    git -C "$WORK" remote add origin "$ORIGIN"
    [ -n "$with_upstream" ] && git -C "$WORK" remote add upstream "$UPSTREAM"
    git -C "$WORK" checkout -q -b master
    echo base > "$WORK/f"
    git -C "$WORK" add f
    git -C "$WORK" commit -qm base
    git -C "$WORK" push -q origin master
    [ -n "$with_upstream" ] && git -C "$WORK" push -q upstream master

    export XDG_CACHE_HOME="$FIXTURE/cache"
    export ORE_CONFIG_PS1_GIT_FETCH_DISABLE=1
    export ORE_CONFIG_PS1_GIT_REFRESH_INTERVAL=0
    export ORE_CONFIG_PS1_GIT_FETCH_INTERVAL=0
    # shellcheck disable=SC1090
    . "$SCRIPT_UNDER_TEST"

    cd "$WORK" || return 1
}

teardown_fixture() {
    cd / || true
    [ -n "$FIXTURE" ] && rm -rf "$FIXTURE"
    unset FIXTURE WORK ORIGIN UPSTREAM
}

# Commit n times on the current branch in $WORK (local-only, => unpushed).
commit_local() {
    local n="$1" i
    for ((i = 1; i <= n; i++)); do
        echo "local $i $RANDOM" >> "$WORK/f"
        git -C "$WORK" commit -qam "local $i"
    done
}

# Advance a bare remote by n commits the work repo's HEAD does not have, by
# pushing from a fresh side clone. advance_remote <bare-repo> <n>
advance_remote() {
    local bare="$1" n="$2" side i
    side="$FIXTURE/side.$RANDOM"
    git clone -q "$bare" "$side"
    git -C "$side" config user.email test@test
    git -C "$side" config user.name test
    git -C "$side" config commit.gpgsign false
    for ((i = 1; i <= n; i++)); do
        echo "remote $i" >> "$side/g"
        git -C "$side" add g
        git -C "$side" commit -qm "remote $i"
    done
    git -C "$side" push -q origin HEAD:master
    rm -rf "$side"
}

# Compute divergence synchronously and echo the cached indicator for the
# current branch. Bypasses the prompt's background spawn for deterministic tests.
indicator_now() {
    local cache
    cache="$(__ore_ps1_git_cache_file)" || { echo ""; return; }
    ( __ore_ps1_git_refresh "$cache" )    # subshell: mirror the detached prompt call
    [ -r "$cache" ] && cat "$cache"
}
