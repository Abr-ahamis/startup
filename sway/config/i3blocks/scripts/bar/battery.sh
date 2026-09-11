#!/usr/bin/env bash
set -u
source "$(dirname "$0")/colors.sh"

# =========================
# Config
# =========================
TEXT="#ffffff"
ICON_COLOR="#a6e3a1"
GREEN="#ffffff"
ORANGE="#ffffff"
MUTED="#ffffff"

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1) ;;
esac

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
  printf "| <span color='%s'>%s</span> <span color='%s'>--%%</span> |\n" "$ICON_COLOR" "$ICON_BATTERY_UNKNOWN" "$TEXT"
  exit 0
fi

pct="$(cat "$bat/capacity" 2>/dev/null || printf 0)"
status="$(cat "$bat/status" 2>/dev/null || printf Unknown)"

icon=""
color="$(percentage_color "$pct")"

if [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
  icon="$ICON_BATTERY_CHARGING"
  color="$HEALTHY"
elif [ "$pct" -gt 80 ]; then
  icon="$ICON_BATTERY_100"
elif [ "$pct" -gt 60 ]; then
  icon="$ICON_BATTERY_75"
elif [ "$pct" -gt 40 ]; then
  icon="$ICON_BATTERY_50"
elif [ "$pct" -gt 20 ]; then
  icon="$ICON_BATTERY_25"
else
  icon="$ICON_BATTERY_0"
fi

# =========================
# Output
# =========================
printf "|<span color='%s'>%s</span> <span color='%s'>%s%%</span>|\n" "$color" "$icon" "$color" "$pct"
