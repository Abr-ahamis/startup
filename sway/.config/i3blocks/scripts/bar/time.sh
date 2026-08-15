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
printf "<span color='%s'>|</span> <span color='%s'>%s</span> %s\n" \
  "$PRIMARY_TEXT" "$PRIMARY_TEXT" "$ICON_TIME" "$(date '+%I:%M')"
