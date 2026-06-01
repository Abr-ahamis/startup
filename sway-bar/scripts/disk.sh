#!/usr/bin/env bash
set -u

MUTED="#6e7681"
TEXT="#c9d1d9"
WARN="#d4902a"
RED="#f85149"
ICON=$'\uf0a0'

pct="$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"
color="$TEXT"
[ "$pct" -ge 90 ] && color="$RED"
[ "$pct" -ge 75 ] && [ "$pct" -lt 90 ] && color="$WARN"

printf "<span color='%s'>%s </span><span color='%s'>%s%%</span>\n" "$MUTED" "| $ICON" "$color" "$pct "
