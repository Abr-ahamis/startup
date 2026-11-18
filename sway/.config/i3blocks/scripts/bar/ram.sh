#!/usr/bin/env bash
set -u
source "$(dirname "$0")/colors.sh"

# =========================
# Config
# =========================
GREEN="#00f845"
YELLOW="#d4902a"
RED="#f85149"
WHITE="#ffffff"
ICON="󰍛"

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    "$HOME/.local/bin/system-monitor.sh" >/dev/null 2>&1 &
    ;;
esac

# =========================
# Memory usage script
# =========================
total_kb=0
available_kb=0
while read -r key value _; do
  case "$key" in
    MemTotal:) total_kb="$value" ;;
    MemAvailable:) available_kb="$value" ;;
  esac
done </proc/meminfo

used_kb=$((total_kb - available_kb))

used_tenths_gb=$((used_kb * 10 / 1024 / 1024))
used_gb="$((used_tenths_gb / 10)).$((used_tenths_gb % 10))"
pct=$((used_kb * 100 / total_kb))

# =========================
# Color logic
# =========================
if (( pct >= 85 )); then
  color="$CRITICAL"
elif (( pct >= 75 )); then
  color="$WARNING"
elif (( pct >= 40 )); then
  color="$ATTENTION"
else
  color="$ACCENT"
fi

# =========================
# Output
# =========================
printf "<span color='%s'> |</span> <span color='%s'>%s</span> <span color='%s'>%s%%</span> <span color='%s'>[%sG]</span>\n" \
  "$PRIMARY_TEXT" "$STABLE_ICON" "$ICON" "$PRIMARY_TEXT" "$pct" "$PRIMARY_TEXT" "$used_gb"
