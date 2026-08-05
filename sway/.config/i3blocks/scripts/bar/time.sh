#!/usr/bin/env bash
set -u

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
  "$TEXT" "$ICON_COLOR" "$ICON_TIME" "$(date '+%I:%M')"
