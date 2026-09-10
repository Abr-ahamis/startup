#!/usr/bin/env bash
set -u
source "$(dirname "$0")/colors.sh"

# =========================
# Config
# =========================
MUTED="#fab387"
TEXT="#ffffff"

# =========================
# Actions
# =========================
#case "${BLOCK_BUTTON:-}" in
#  1)
#    foot -e bash -ic 'exec btop' >/dev/null 2>&1 &
#  ;;
#esac

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_CALENDAR=""

# =========================
# Logic + Output
# =========================
# Color only the icon with $MUTED; make surrounding text white ($TEXT).
# Output layout: | <icon> <date>
printf "<span color='%s'>|</span> <span color='%s'>%s</span> <span color='%s'>%s</span>\n" \
  "$PRIMARY_TEXT" "$SECONDARY_TEXT" "$ICON_CALENDAR" "$SECONDARY_TEXT" "$(date '+%Y-%m(%b)-%d')"
