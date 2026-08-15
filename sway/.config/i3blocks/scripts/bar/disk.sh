#!/usr/bin/env bash
set -u
source "$(dirname "$0")/colors.sh"

# =========================
# Config
# =========================
WHITE="#ffffff"
ICON_COLOR="#f9e2af"
GREEN="#ffffff"
YELLOW="#ffffff"
RED="#ffffff"

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    foot -e btop >/dev/null 2>&1 &
    ;;
esac

# =========================
# Icon
# =========================
ICON_DISK=""

# =========================
# Logic (exact GB with decimal)
# =========================
free_bytes="$(df -B1 / | awk 'NR==2 {print $4}')"
free_gb="$(awk -v b="$free_bytes" 'BEGIN {printf "%.1f", b/1024/1024/1024}')"
used_pct="$(df -P / | awk 'NR==2 {gsub(/%/, "", $5); print $5}')"

# =========================
# Color logic
# =========================
color="$(percentage_color "$used_pct")"

# =========================
# Output
# =========================
printf "<span color='%s'>| </span><span color='%s'>%s</span> <span color='%s'>%sG</span>\n" \
  "$PRIMARY_TEXT" "$color" "$ICON_DISK" "$color" "$free_gb"
