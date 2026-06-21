#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
TEXT="#c9d1d9"
GREEN="#3fb950"
ORANGE="#c98a2d"
MUTED="#6e7681"

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_BATTERY_CHARGING=""
ICON_BATTERY_100=""
ICON_BATTERY_75=""
ICON_BATTERY_50=""
ICON_BATTERY_25=""
ICON_BATTERY_0=""
ICON_BATTERY_UNKNOWN=""

# =========================
# Helpers
# =========================
get_battery_path() {
  find /sys/class/power_supply -maxdepth 1 -type l -name 'BAT*' | head -n 1
}

# =========================
# Logic
# =========================
bat="$(get_battery_path)"

if [ -z "$bat" ]; then
  printf "<span color='%s'>%s --%%</span>\n" "$MUTED" "$ICON_BATTERY_UNKNOWN"
  exit 0
fi

pct="$(cat "$bat/capacity" 2>/dev/null || printf 0)"
status="$(cat "$bat/status" 2>/dev/null || printf Unknown)"

icon=""
color="$TEXT"

if [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
  icon="$ICON_BATTERY_CHARGING"
  color="$GREEN"

elif [ "$pct" -gt 80 ]; then
  icon="$ICON_BATTERY_100"
  color="$TEXT"

elif [ "$pct" -gt 60 ]; then
  icon="$ICON_BATTERY_75"
  color="$TEXT"

elif [ "$pct" -gt 40 ]; then
  icon="$ICON_BATTERY_50"
  color="$TEXT"

elif [ "$pct" -gt 20 ]; then
  icon="$ICON_BATTERY_25"
  color="$TEXT"

else
  icon="$ICON_BATTERY_0"
  color="$ORANGE"
fi

# =========================
# Output
# =========================
printf "| <span color='%s'>%s %s%%</span>\n" "$color" "$icon" "$pct"