#!/usr/bin/env bash
set -u

TEXT="#c9d1d9"
GREEN="#3fb950"
ORANGE="#c98a2d"
MUTED="#6e7681"

bat="$(find /sys/class/power_supply -maxdepth 1 -type l -name 'BAT*' | head -n 1)"
if [ -z "$bat" ]; then
  printf "<span color='%s'>%s --%%</span>\n" "$MUTED" $'\uf244'
  exit 0
fi

pct="$(cat "$bat/capacity" 2>/dev/null || printf 0)"
status="$(cat "$bat/status" 2>/dev/null || printf Unknown)"

if [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
  icon=$'\uf376'; color="$GREEN"
elif [ "$pct" -gt 80 ]; then
  icon=$'\uf240'; color="$TEXT"
elif [ "$pct" -gt 60 ]; then
  icon=$'\uf241'; color="$TEXT"
elif [ "$pct" -gt 40 ]; then
  icon=$'\uf242'; color="$TEXT"
elif [ "$pct" -gt 20 ]; then
  icon=$'\uf243'; color="$TEXT"
else
  icon=$'\uf244'; color="$ORANGE"
fi

printf "<span color='%s'>%s %s%%</span>\n" "$color" "| $icon" "$pct"
