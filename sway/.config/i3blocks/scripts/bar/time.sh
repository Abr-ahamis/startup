#!/usr/bin/env bash
set -u
source "$(dirname "$0")/colors.sh"

# =========================
# Config
# =========================
TEXT="#ffffff"
ICON_COLOR="#89b4fa"

# =========================
# Actions
# =========================
#case "${BLOCK_BUTTON:-}" in
#  1) ;;
#esac

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_TIME=""

# =========================
# Logic + Output
# =========================
printf "<span color='%s'>|</span> <span color='%s'>%s</span> <span color='%s'>%s</span>\n" \
  "$PRIMARY_TEXT" "$STABLE_ICON" "$ICON_TIME" "$PRIMARY_TEXT" "$(date '+%I:%M')"
