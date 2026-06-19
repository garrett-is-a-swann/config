# Per-remote ahead/behind indicator for the git section of PS1.
#
# Wraps the stock __git_ps1 so the prompt shows, per remote, how the local HEAD
# diverges from that remote's tracking ref for the current branch:
#
#   :master:                          no disparity with any remote
#   :master[origin(-5)]:              5 commits not yet pushed to origin
#   :master[origin(-5)|upstream(+6/-5)]:
#                                     origin is 5 behind HEAD; upstream is 6
#                                     ahead (to pull) and 5 behind (to push)
#
# Signs are from the remote's point of view: -N = remote is behind HEAD (you
# have N unpushed commits); +N = remote is ahead (N commits to pull).
#
# Freshness has two paths:
#   * Local — divergence vs the remote-tracking refs is a local computation, so
#     the prompt recomputes it on the spot whenever a ref actually moved (your
#     commit/push/fetch bumps a file under .git, cheaply detected by mtime).
#     Steady-state prompts just read the cache.
#   * Remote — a detached, throttled refresher runs `git fetch` out of band so a
#     remote that moved ahead is eventually noticed without you fetching; that
#     fetch updates the tracking refs, which the local path then picks up.
# Either way the prompt issues no blocking network call.
#
# Knobs (all optional):
#   ORE_CONFIG_PS1_GIT_FETCH_DISABLE     non-empty -> never fetch in background
#   ORE_CONFIG_PS1_GIT_REFRESH_INTERVAL  min seconds between background passes (def 5)
#   ORE_CONFIG_PS1_GIT_FETCH_INTERVAL    min seconds between fetches           (def 300)

__ore_ps1_git_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/ore-config/ps1-git-ahead-behind"

# Cache path for a given git dir + branch. Pure string assembly, no forks.
__ore_ps1_git_cache_path() {
    printf '%s/%s__%s' "$__ore_ps1_git_cache_dir" "${1//\//%}" "${2//\//%}"
}

# Cache file for the current repo + branch. Echoes the path; non-zero if not on
# a named branch. One git invocation (no network).
__ore_ps1_git_cache_file() {
    local info gitdir branch
    info="$(git rev-parse --absolute-git-dir --abbrev-ref HEAD 2>/dev/null)" || return 1
    gitdir="${info%%$'\n'*}"
    branch="${info##*$'\n'}"
    [ -n "$gitdir" ] && [ -n "$branch" ] && [ "$branch" != HEAD ] || return 1
    __ore_ps1_git_cache_path "$gitdir" "$branch"
}

# True if any ref under <gitdir> is newer than <cache> — i.e. a commit, push,
# fetch, merge, reset, etc. has moved a ref since the cache was last written.
# Uses find -newer (no git, stops at the first hit); missing paths are ignored.
__ore_ps1_git_refs_changed() {
    [ -n "$(find "$1/refs" "$1/logs" "$1/packed-refs" "$1/FETCH_HEAD" \
        -newer "$2" -print -quit 2>/dev/null)" ]
}

# Compute per-remote divergence for the cwd repo and atomically write <cache>.
# Local only: compares HEAD to each remote-tracking ref, no network. $BASHPID
# (not $$) keeps the temp file unique when foreground and background race.
__ore_ps1_git_compute() {
    local cache="$1" branch out="" remote counts ahead behind part
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
    for remote in $(git remote); do
        git rev-parse --verify --quiet "refs/remotes/$remote/$branch" >/dev/null 2>&1 || continue
        counts="$(git rev-list --count --left-right "refs/remotes/$remote/$branch...HEAD" 2>/dev/null)" || continue
        read -r ahead behind <<< "$counts"   # left = remote-ahead, right = HEAD-ahead
        part=""
        [ "${ahead:-0}" -gt 0 ] 2>/dev/null && part="+$ahead"
        [ "${behind:-0}" -gt 0 ] 2>/dev/null && part="$part${part:+/}-$behind"
        [ -n "$part" ] && out="$out${out:+|}$remote($part)"
    done

    local indicator=""
    [ -n "$out" ] && indicator="[$out]"
    mkdir -p "$__ore_ps1_git_cache_dir" 2>/dev/null
    printf '%s' "$indicator" > "$cache.tmp.$BASHPID" && mv -f "$cache.tmp.$BASHPID" "$cache"
}

# Background worker: throttle, optionally fetch, then recompute. Runs detached,
# so its (network) latency never reaches the prompt. The fetch is what the
# foreground path can't do; the recompute keeps the cache warm after it.
__ore_ps1_git_refresh() {
    local cache="$1"
    local stamp="$cache.stamp" lock="$cache.lock"
    local now interval="${ORE_CONFIG_PS1_GIT_REFRESH_INTERVAL:-5}"
    printf -v now '%(%s)T' -1

    if [ -f "$stamp" ]; then
        local last; last="$(<"$stamp")"
        [ $((now - last)) -lt "$interval" ] && return 0
    fi

    mkdir -p "$__ore_ps1_git_cache_dir" 2>/dev/null
    # Break a lock left behind by a refresher that was killed before cleanup.
    [ -d "$lock" ] && [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ] &&
        rmdir "$lock" 2>/dev/null
    # Single-flight: an atomic mkdir is the lock.
    mkdir "$lock" 2>/dev/null || return 0
    printf '%s\n' "$now" > "$stamp"

    if [ -z "${ORE_CONFIG_PS1_GIT_FETCH_DISABLE:-}" ]; then
        local fstamp="$cache.fetch" finterval="${ORE_CONFIG_PS1_GIT_FETCH_INTERVAL:-300}" flast=0
        [ -f "$fstamp" ] && flast="$(<"$fstamp")"
        if [ $((now - flast)) -ge "$finterval" ]; then
            printf '%s\n' "$now" > "$fstamp"
            git fetch --quiet --all --no-tags 2>/dev/null
        fi
    fi

    __ore_ps1_git_compute "$cache"

    rmdir "$lock" 2>/dev/null
}

# Drop-in replacement for $(__git_ps1 "%s:") in PS1. Emits "branch[indicator]:"
# inside a repo, nothing outside it.
__git_ps1_ahead_behind() {
    local gs
    gs="$(__git_ps1 '%s')"
    [ -n "$gs" ] || return 0

    local info gitdir branch
    info="$(git rev-parse --absolute-git-dir --abbrev-ref HEAD 2>/dev/null)"
    gitdir="${info%%$'\n'*}"
    branch="${info##*$'\n'}"

    local indicator=""
    if [ -n "$gitdir" ] && [ -n "$branch" ] && [ "$branch" != HEAD ]; then
        local cache; cache="$(__ore_ps1_git_cache_path "$gitdir" "$branch")"
        # Recompute now if a ref moved since the cache (commit/push/fetch/...) —
        # local-only, so it's cheap and only fires right after a git operation.
        if [ ! -r "$cache" ] || __ore_ps1_git_refs_changed "$gitdir" "$cache"; then
            __ore_ps1_git_compute "$cache"
        fi
        [ -r "$cache" ] && read -r indicator < "$cache"
        # Detached pass keeps the remote side fresh (throttled background fetch).
        ( __ore_ps1_git_refresh "$cache" & ) >/dev/null 2>&1
    fi

    printf '%s%s:' "$gs" "$indicator"
}
