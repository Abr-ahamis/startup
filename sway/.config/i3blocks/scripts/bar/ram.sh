#!/usr/bin/env bash
set -u

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
    foot -e btop >/dev/null 2>&1 &
    ;;
esac

# =========================
# Memory usage script
# =========================
total_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
available_kb="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"

used_kb=$((total_kb - available_kb))

used_gb="$(awk -v kb="$used_kb" 'BEGIN {printf "%.1f", kb/1024/1024}')"
pct="$(awk -v used="$used_kb" -v total="$total_kb" 'BEGIN {printf "%.0f", (used/total)*100}')"

# =========================
# Color logic
# =========================
color="$GREEN"

awk -v p="$pct" 'BEGIN {exit !(p >= 80)}' && color="$RED"
awk -v p="$pct" 'BEGIN {exit !(p >= 50 && p < 80)}' && color="$YELLOW"

# =========================
# Output
# =========================
printf "<span color='%s'> |</span> <span color='%s'>%s</span> <span color='%s'>%s%%</span> <span color='%s'>[%sG]</span>\n" \
  "$WHITE" "$color" "$ICON" "$WHITE" "$pct" "$WHITE" "$used_gb"
