#!/usr/bin/env bash
# Live prompt-cache HUD — ticks every second, independent of Claude Code's
# message-driven statusline refresh. Run it in a side pane / split:
#
#     ~/.claude/bin/stats/cache-hud.sh                 # auto-tracks the active session
#     ~/.claude/bin/stats/cache-hud.sh /path/to.jsonl  # pin to one transcript
#
# Watches the most-recently-modified transcript so it follows whatever
# session you're actively typing in.
RESET=$'\033[0m'; GRAY=$'\033[90m'; BG=$'\033[92m'; BY=$'\033[93m'; BR=$'\033[91m'; BB=$'\033[94m'
PROJ="$HOME/.claude/projects"
STATS="$HOME/.claude/bin/stats/cache-session-stats.py"
TTL=3600   # Claude Code uses the 1-hour extended cache TTL

active_transcript() { ls -t "$PROJ"/*/*.jsonl 2>/dev/null | head -1; }

trap 'printf "\033[?25h\n"; exit 0' INT TERM   # restore cursor on exit
printf '\033[?25l'                              # hide cursor

while :; do
    f="${1:-$(active_transcript)}"
    if [ -z "$f" ] || [ ! -f "$f" ]; then
        printf '\r\033[K%s(no active session)%s' "$GRAY" "$RESET"; sleep 1; continue
    fi
    line=$(tail -c 262144 "$f" | grep -a 'cache_read_input_tokens' | tail -1)
    ts=$(printf '%s' "$line" | jq -r '.timestamp // ""' 2>/dev/null)
    now=$(date +%s); last=$(date -d "$ts" +%s 2>/dev/null || echo "$now")
    rem=$((TTL - (now - last)))            # TTL=1h extended cache

    read -r miss good waste lm lr < <(python3 "$STATS" "$f" 2>/dev/null || echo "0 0 0 0 0")
    wk=$(awk -v n="$waste" 'BEGIN{ if(n>=1e6)printf"%.1fM",n/1e6; else if(n>=1e3)printf"%.0fk",n/1e3; else printf"%d",n }')

    if [ "$rem" -le 0 ]; then
        timer="${BB}❄ COLD — next turn re-writes the prefix${RESET}"
    else
        if   [ "$rem" -gt 600 ]; then tc=$BG; elif [ "$rem" -gt 120 ]; then tc=$BY; else tc=$BR; fi
        timer=$(printf "%b⚡ %d:%02d to cold%b" "$tc" $((rem/60)) $((rem%60)) "$RESET")
    fi
    if   [ "${miss:-0}" -eq 0 ]; then mc=$GRAY; elif [ "${miss:-0}" -lt 3 ]; then mc=$BY; else mc=$BR; fi
    [ "${lm:-0}" = "1" ] && last_t="${BR}✗miss${RESET}" || last_t="${GRAY}⟲hit${RESET}"

    printf '\r\033[K  %s   %s last   %s✗%s misses%s   %s⊘%s wasted%s' \
        "$timer" "$last_t" "$mc" "${miss:-0}" "$RESET" "$GRAY" "$wk" "$RESET"
    sleep 1
done
