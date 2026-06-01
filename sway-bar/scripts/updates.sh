#!/usr/bin/env bash
set -u

MUTED="#6e7681"
WARN="#d4902a"
ICON=$'\uf021'
count=0

if command -v checkupdates >/dev/null 2>&1; then
  count="$(checkupdates 2>/dev/null | wc -l)"
elif command -v apt >/dev/null 2>&1; then
  count="$(apt list --upgradeable 2>/dev/null | awk 'NR>1 {c++} END {print c+0}')"
fi

color="$MUTED"
[ "$count" -gt 0 ] && color="$WARN"
printf "<span color='%s'>%s </span><span color='%s'>%s</span>\n" "$MUTED" "| $ICON " "$color" "$count "
