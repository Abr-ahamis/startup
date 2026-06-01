#!/usr/bin/env bash
set -u

MUTED="#6e7681"
TEXT="#c9d1d9"
WARN="#d4902a"
RED="#f85149"
ICON=$'\uf538'

total="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
available="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
used=$((total - available))
pct=$((100 * used / total))
used_g="$(awk -v kb="$used" 'BEGIN {printf "%.1f", kb/1048576}')"

color="$TEXT"
[ "$pct" -ge 85 ] && color="$RED"
[ "$pct" -ge 65 ] && [ "$pct" -lt 85 ] && color="$WARN"

printf "<span color='%s'>%s </span><span color='%s'>%sG</span>\n" "$MUTED" "$ICON" "$color" "$used_g"
