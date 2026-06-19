#!/usr/bin/env bash
# =============================== CONFIG ===============================
# The status line is a grid. Each element is placed with a token of the
# form  <elem><col>:<row>  (1-based). Columns are right-padded so they
# line up vertically; cells on a row are joined by SEP. Rearrange the
# status line by editing these three values.
#
#   elements:  m=model  g=git  h=5h window  c=context  w=7d window
#              k=previous turn cache result (⟲56k warm hit / ✗56k real miss)
#              x=session cache misses (✗N)  e=wasted tokens (⊘N!ratio×)
#
LAYOUT="m1:1 h2:1 g3:1 c1:2 w2:2 k3:2 x1:3 e2:3"
SEP=":"
USAGE_COLOR=36          # usage% color; the 5h window uses its bright (9x) variant
# ======================================================================

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd')
ESC=$'\033'

# Colors
RESET="\033[00m"
YELLOW="\033[00;33m"
CYAN="\033[00;36m"
GREEN="\033[01;32m"
BLUE="\033[00;34m"
RED="\033[00;31m"
GRAY="\033[90m"
WHITE="\033[37m"
BGREEN="\033[92m"; BYELLOW="\033[93m"; BRED="\033[91m"; BBLUE="\033[94m"
U="\033[${USAGE_COLOR}m"
if [[ "$USAGE_COLOR" =~ ^3[0-7]$ ]]; then UB="\033[$((USAGE_COLOR + 60))m"; else UB="$U"; fi

# Pick a color for a "higher is worse" value. Optional low/high thresholds
# (default 33/66) and a non-empty 4th arg to use the bright variants.
threshold_color() {
    local value=$1 low=${2:-33} high=${3:-66} bright=$4 g=$GREEN y=$YELLOW r=$RED
    [ -n "$bright" ] && { g=$BGREEN; y=$BYELLOW; r=$BRED; }
    if [ "$value" -lt "$low" ]; then printf '%s' "$g"
    elif [ "$value" -lt "$high" ]; then printf '%s' "$y"
    else printf '%s' "$r"; fi
}

# 200000 -> 200k, 1500000 -> 1.5M.
human_num() {
    awk -v n="$1" 'BEGIN {
        if (n >= 1000000) printf "%.1fM", n / 1000000;
        else if (n >= 1000) printf "%.0fk", n / 1000;
        else printf "%g", n;
    }'
}

window_seconds() { case "$1" in five_hour) printf '%s' 18000 ;; seven_day) printf '%s' 604800 ;; esac; }

# Visible width: strip SGR escapes, then count UTF-8 code points (drop
# continuation bytes so multibyte chars like the arrow count as 1).
vlen() {
    local s; s=$(printf '%s' "$1" | sed "s/${ESC}\[[0-9;]*m//g")
    printf '%s' "$s" | LC_ALL=C tr -d '\200-\277' | LC_ALL=C wc -c | tr -dc '0-9'
}

# ---- element renderers: print a rendered cell, or nothing if absent ----
elem_model() {
    local model agent suffix=""
    model=$(echo "$input" | jq -r '.model.display_name // .model.id // ""')
    agent=$(echo "$input" | jq -r '.agent.name // ""')
    [ -n "$agent" ] && [ "$agent" != "null" ] && suffix="@${agent}"
    printf "%b" "${YELLOW}${model}${suffix}${RESET}"
}

elem_git() {
    local branch=""
    if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
        branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    fi
    [ -z "$branch" ] && return
    printf "%b" "${GREEN}(${branch})${RESET}"
}

elem_context() {
    local used_pct used_int size allot=""
    used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // ""')
    [ -z "$used_pct" ] || [ "$used_pct" = "null" ] && return
    used_int=$(printf "%.0f" "$used_pct")
    size=$(echo "$input" | jq -r '.context_window.context_window_size // ""')
    [ -n "$size" ] && [ "$size" != "null" ] && allot="${WHITE}@${YELLOW}$(human_num "$size")"
    printf "%b" "${GRAY}↳${RESET}${CYAN}c$(printf '%2d' "$used_int")%${allot}${RESET}"
}

# elem_window <rate_limit_key> <label> [bright]
# Renders [label:uNN%@<remaining><unit>(elapsed%)!<pace>%] for a rate window.
elem_window() {
    local key=$1 label=$2 bright=$3
    local usage_pct resets_at usage_int dur secs remaining unit elapsed over headroom uc tc pc
    usage_pct=$(echo "$input" | jq -r ".rate_limits.${key}.used_percentage // \"\"")
    resets_at=$(echo "$input" | jq -r ".rate_limits.${key}.resets_at // \"\"")
    [ -z "$usage_pct" ] || [ "$usage_pct" = "null" ] && return
    [ -z "$resets_at" ] || [ "$resets_at" = "null" ] && return
    usage_int=$(printf "%.0f" "$usage_pct")
    dur=$(window_seconds "$key")
    secs=$((resets_at - $(date +%s)))
    if [ "$dur" -ge 86400 ]; then remaining=$(awk "BEGIN{printf \"%.1f\", $secs/86400}"); unit="d"
    else remaining=$(awk "BEGIN{printf \"%.1f\", $secs/3600}"); unit="h"; fi
    elapsed=$(awk "BEGIN{printf \"%.0f\", ($dur - $secs)/$dur*100}")
    over=$((usage_int - elapsed)); headroom=$((elapsed - usage_int))
    if [ -n "$bright" ]; then uc=$UB; tc=$BBLUE; else uc=$U; tc=$BLUE; fi
    pc=$(threshold_color "$over" -5 6 "$bright")
    printf "%b" "[${GRAY}${label}:${RESET}${uc}u$(printf '%2d' "$usage_int")%${RESET}@${tc}${remaining}${unit}($(printf '%2d' "$elapsed")%)${RESET}!${pc}$(printf '%+3d' "$headroom")%${RESET}]"
}

# Previous turn's cache outcome (accurate whenever rendered — unlike a live
# countdown, which the statusline can't tick during idle). Shows the warm
# prefix served on a hit (⟲56k) or flags a real miss that re-wrote the prefix
# (✗56k). The live ticking countdown lives in ~/.claude/bin/stats/cache-hud.sh instead.
elem_cache() {
    local miss good waste lm lr
    read -r miss good waste lm lr <<<"$(session_stats)"
    [ -z "$lr" ] && return
    if [ "$lm" = "1" ]; then
        printf "%b" "${BRED}✗$(human_num "$lr")${RESET}"
    else
        printf "%b" "${GRAY}⟲${RESET}${BGREEN}$(human_num "$lr")${RESET}"
    fi
}

# Session cache stats (memoized helper). Echoes "<misses> <good> <wasted>".
session_stats() {
    local transcript
    transcript=$(echo "$input" | jq -r '.transcript_path // ""')
    { [ -z "$transcript" ] || [ "$transcript" = "null" ] || [ ! -f "$transcript" ]; } && { echo "0 0 0 0 0"; return; }
    python3 ~/.claude/bin/stats/cache-session-stats.py "$transcript" 2>/dev/null || echo "0 0 0 0 0"
}

# Count of real cache misses this session (prefix re-writes).
elem_miss() {
    local miss good waste lm lr color
    read -r miss good waste lm lr <<<"$(session_stats)"
    if   [ "$miss" -eq 0 ]; then color=$GRAY
    elif [ "$miss" -lt 3 ]; then color=$BYELLOW
    else color=$BRED; fi
    printf "%b" "${color}✗${miss}${RESET}"
}

# Wasted (re-written) tokens this session, with a "restarts burned" ratio:
# wasted / current-context-tokens. >=1x means misses have already cost more
# than a clean restart would — a signal to /compact or abandon.
elem_waste() {
    local miss good waste lm lr used_pct size used ratio rcol wcol
    read -r miss good waste lm lr <<<"$(session_stats)"
    used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // ""')
    size=$(echo "$input" | jq -r '.context_window.context_window_size // ""')
    wcol=$(threshold_color "$((waste / 1000))" 20 100 bright)
    if [ -n "$used_pct" ] && [ "$used_pct" != "null" ] && [ -n "$size" ] && [ "$size" != "null" ]; then
        used=$(awk "BEGIN{printf \"%d\", $used_pct/100*$size}")
        if [ "$used" -gt 0 ]; then
            ratio=$(awk "BEGIN{printf \"%.1f\", $waste/$used}")
            rcol=$(awk "BEGIN{print ($ratio<1)?0:($ratio<2)?1:2}")
            case $rcol in 0) rcol=$BGREEN;; 1) rcol=$BYELLOW;; *) rcol=$BRED;; esac
            printf "%b" "${GRAY}⊘${RESET}${wcol}$(human_num "$waste")${RESET}${GRAY}!${RESET}${rcol}${ratio}×${RESET}"
            return
        fi
    fi
    printf "%b" "${GRAY}⊘${RESET}${wcol}$(human_num "$waste")${RESET}"
}

render_elem() {
    case "$1" in
        m) elem_model ;;
        g) elem_git ;;
        h) elem_window five_hour 5h bright ;;
        c) elem_context ;;
        w) elem_window seven_day 7d ;;
        k) elem_cache ;;
        x) elem_miss ;;
        e) elem_waste ;;
    esac
}

# ---- grid engine: place cells, size columns, emit aligned rows ----
declare -A CELL WIDTH COLW
maxcol=1; maxrow=1
for tok in $LAYOUT; do
    id="${tok:0:1}"; rest="${tok:1}"; rest="${rest#:}"
    col="${rest%%:*}"; row="${rest##*:}"
    [ -z "$col" ] && col=1; [ -z "$row" ] && row=1
    cell=$(render_elem "$id")
    CELL["$col,$row"]="$cell"
    cw=$(vlen "$cell"); WIDTH["$col,$row"]=$cw
    [ "$col" -gt "$maxcol" ] && maxcol=$col
    [ "$row" -gt "$maxrow" ] && maxrow=$row
    [ "$cw" -gt "${COLW[$col]:-0}" ] && COLW[$col]=$cw
done

out=""
for ((r=1; r<=maxrow; r++)); do
    lastcol=0
    for ((col=1; col<=maxcol; col++)); do [ -n "${CELL[$col,$r]}" ] && lastcol=$col; done
    line=""
    for ((col=1; col<=lastcol; col++)); do
        content="${CELL[$col,$r]}"
        if [ "$col" -lt "$lastcol" ]; then
            printf -v cellstr '%s%*s' "$content" "$(( ${COLW[$col]:-0} - ${WIDTH[$col,$r]:-0} ))" ''
        else
            cellstr="$content"
        fi
        [ "$col" -eq 1 ] && line="$cellstr" || line="${line}${SEP}${cellstr}"
    done
    [ "$r" -eq 1 ] && out="$line" || out="${out}"$'\n'"${line}"
done
printf '%s\n' "$out"
