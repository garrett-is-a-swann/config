#!/usr/bin/env bash
# Unit tests for bash/git-ps1-ahead-behind.sh.
# Run via ./run.sh, or directly: bash git-ps1-ahead-behind.test.sh
#
# No `set -u`: the script wraps the stock git-sh-prompt, which is not
# nounset-clean, and it runs in ordinary interactive shells that never set it.
cd "$(dirname "${BASH_SOURCE[0]}")"
. ./helpers.sh

# --- divergence rendering -------------------------------------------------

test_clean_tree_has_no_indicator() {
    new_fixture
    assert_empty "$(indicator_now)" "clean tree: no indicator"
    teardown_fixture
}

test_unpushed_renders_minus() {
    new_fixture
    commit_local 5    # 5 commits origin lacks => remote is 5 behind HEAD
    assert_eq "[origin(-5)]" "$(indicator_now)" "unpushed commits render -N"
    teardown_fixture
}

test_remote_ahead_renders_plus() {
    new_fixture
    advance_remote "$ORIGIN" 3
    git fetch -q origin     # refresh remote-tracking ref (fetch disabled in helper)
    assert_eq "[origin(+3)]" "$(indicator_now)" "remote-ahead commits render +N"
    teardown_fixture
}

test_diverged_renders_plus_then_minus() {
    new_fixture
    advance_remote "$ORIGIN" 6
    git fetch -q origin
    commit_local 5
    assert_eq "[origin(+6/-5)]" "$(indicator_now)" "diverged renders (+ahead/-behind)"
    teardown_fixture
}

test_multi_remote_matches_task_example() {
    new_fixture --with-upstream
    commit_local 5                      # both remotes 5 behind HEAD
    advance_remote "$UPSTREAM" 6        # upstream gains 6 HEAD lacks
    git fetch -q upstream
    assert_eq "[origin(-5)|upstream(+6/-5)]" "$(indicator_now)" \
        "multi-remote matches the task's worked example"
    teardown_fixture
}

test_remote_without_tracking_ref_is_skipped() {
    new_fixture --with-upstream
    # never pushed a fresh branch to upstream; create branch only locally
    git -C "$WORK" checkout -q -b feature
    commit_local 2
    git -C "$WORK" push -q origin feature
    git fetch -q origin
    # origin has feature (2 behind HEAD after the push? no — push made them equal),
    # upstream has no feature ref at all and must be silently skipped.
    assert_empty "$(indicator_now)" "remote lacking the branch ref is skipped"
    teardown_fixture
}

# --- branch name handling -------------------------------------------------

test_slashed_branch_name() {
    new_fixture
    git -C "$WORK" checkout -q -b feature/login
    commit_local 1
    git -C "$WORK" push -q origin feature/login
    git fetch -q origin
    commit_local 2     # 2 unpushed on the slashed branch
    assert_eq "[origin(-2)]" "$(indicator_now)" "slashed branch name works (cache key sanitized)"
    teardown_fixture
}

test_detached_head_has_no_cache_file() {
    new_fixture
    commit_local 1
    git -C "$WORK" checkout -q --detach
    # no named branch => no cache file, and no crash
    assert_eq "1" "$(__ore_ps1_git_cache_file >/dev/null 2>&1; echo $?)" \
        "detached HEAD yields no cache file (rc=1)"
    teardown_fixture
}

# --- prompt wrapper (needs the stock __git_ps1) ---------------------------

test_wrapper_output() {
    if [ ! -r /usr/lib/git-core/git-sh-prompt ]; then
        printf 'ok %d - # SKIP wrapper test (git-sh-prompt not found)\n' "$((TESTS_RUN + 1))"
        TESTS_RUN=$((TESTS_RUN + 1))
        return
    fi
    new_fixture
    # shellcheck disable=SC1091
    . /usr/lib/git-core/git-sh-prompt
    indicator_now >/dev/null                 # prime cache: clean
    assert_eq "master:" "$(__git_ps1_ahead_behind)" "wrapper: clean tree -> branch:"

    commit_local 4
    indicator_now >/dev/null                 # prime cache: 4 unpushed
    assert_eq "master[origin(-4)]:" "$(__git_ps1_ahead_behind)" "wrapper: unpushed -> branch[indicator]:"

    cd "$FIXTURE"                            # outside a work tree
    assert_empty "$(__git_ps1_ahead_behind)" "wrapper: outside a repo -> empty"
    teardown_fixture
}

# --- throttling & background fetch ----------------------------------------

test_recompute_is_throttled() {
    new_fixture
    export ORE_CONFIG_PS1_GIT_REFRESH_INTERVAL=3600   # effectively never re-runs
    local cache; cache="$(__ore_ps1_git_cache_file)"
    ( __ore_ps1_git_refresh "$cache" )                # first run: clean -> ""
    commit_local 3                                    # now 3 unpushed...
    ( __ore_ps1_git_refresh "$cache" )                # ...but throttle should skip recompute
    assert_empty "$(cat "$cache")" "recompute respects the throttle window (cache stays stale)"
    teardown_fixture
}

test_background_fetch_picks_up_remote_ahead() {
    new_fixture
    unset ORE_CONFIG_PS1_GIT_FETCH_DISABLE            # enable auto-fetch
    export ORE_CONFIG_PS1_GIT_FETCH_INTERVAL=0        # fetch every refresh
    advance_remote "$ORIGIN" 2                        # remote moves ahead; local ref still stale
    # local tracking ref is stale, so without fetch the indicator would be empty;
    # the refresher's own `git fetch` must update it.
    assert_eq "[origin(+2)]" "$(indicator_now)" "background fetch updates remote-ahead"
    teardown_fixture
}

test_fetch_disable_is_respected() {
    new_fixture                                       # helper sets FETCH_DISABLE=1
    advance_remote "$ORIGIN" 2
    # with fetch disabled and a stale tracking ref, no divergence is visible
    assert_empty "$(indicator_now)" "fetch disable: no background fetch, stale ref stays stale"
    teardown_fixture
}

# --- recompute-on-change (local ref moved) --------------------------------

test_refs_changed_detector() {
    new_fixture
    local cache gitdir r
    cache="$(__ore_ps1_git_cache_file)"
    gitdir="$(git rev-parse --absolute-git-dir)"
    __ore_ps1_git_compute "$cache"          # cache written now; fixture refs are older
    if __ore_ps1_git_refs_changed "$gitdir" "$cache"; then r=changed; else r=steady; fi
    assert_eq "steady" "$r" "refs_changed: steady state -> false"
    commit_local 1                          # moves refs/heads/master
    if __ore_ps1_git_refs_changed "$gitdir" "$cache"; then r=changed; else r=steady; fi
    assert_eq "changed" "$r" "refs_changed: after a commit -> true"
    teardown_fixture
}

test_wrapper_recomputes_on_ref_change() {
    if [ ! -r /usr/lib/git-core/git-sh-prompt ]; then
        printf 'ok %d - # SKIP recompute-on-change (git-sh-prompt not found)\n' "$((TESTS_RUN + 1))"
        TESTS_RUN=$((TESTS_RUN + 1))
        return
    fi
    new_fixture
    # shellcheck disable=SC1091
    . /usr/lib/git-core/git-sh-prompt
    # Park the detached background pass so only the foreground recompute writes
    # the cache — isolates the on-change path under test.
    export ORE_CONFIG_PS1_GIT_REFRESH_INTERVAL=3600
    local cache; cache="$(__ore_ps1_git_cache_file)"
    mkdir -p "$__ore_ps1_git_cache_dir"
    printf '%(%s)T\n' -1 > "$cache.stamp"

    assert_eq "master:" "$(__git_ps1_ahead_behind)" "wrapper: clean before any op"
    commit_local 2                          # a local ref moves...
    assert_eq "master[origin(-2)]:" "$(__git_ps1_ahead_behind)" \
        "wrapper recomputes on a local ref change without a manual refresh"
    teardown_fixture
}

test_clean_tree_has_no_indicator
test_unpushed_renders_minus
test_remote_ahead_renders_plus
test_diverged_renders_plus_then_minus
test_multi_remote_matches_task_example
test_remote_without_tracking_ref_is_skipped
test_slashed_branch_name
test_detached_head_has_no_cache_file
test_wrapper_output
test_recompute_is_throttled
test_background_fetch_picks_up_remote_ahead
test_fetch_disable_is_respected
test_refs_changed_detector
test_wrapper_recomputes_on_ref_change

printf '1..%d\n' "$TESTS_RUN"
[ "$TESTS_FAILED" -eq 0 ] || exit 1
