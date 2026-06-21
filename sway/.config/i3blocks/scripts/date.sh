#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
MUTED="#6e7681"
TEXT="#c9d1d9"

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_CALENDAR=""

# =========================
# Logic + Output
# =========================
printf "<span color='%s'>| %s </span><span color='%s'>%s</span>\n" \
  "$MUTED" "$ICON_CALENDAR" "$TEXT" "$(date '+%Y-%m-%d')"