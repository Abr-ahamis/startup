#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
TEXT="#c9d1d9"

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_TIME=""

# =========================
# Logic + Output
# =========================
printf "<span font_weight='bold' color='%s'>| %s %s</span>\n" \
  "$TEXT" "$ICON_TIME" "$(date '+%H:%M')"