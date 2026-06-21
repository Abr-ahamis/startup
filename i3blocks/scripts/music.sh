#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
TEXT="#c9d1d9"
MUTED="#6e7681"
OFF="#4a5568"

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_PREV=""
ICON_PLAY=""
ICON_PAUSE=""
ICON_NEXT=""

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1) playerctl previous >/dev/null 2>&1 || true ;;
  2) playerctl play-pause >/dev/null 2>&1 || true ;;
  3) playerctl next >/dev/null 2>&1 || true ;;
esac

# =========================
# Logic
# =========================
status="$(playerctl status 2>/dev/null || printf Stopped)"

icon_center=""
color="$OFF"

case "$status" in
  Playing)
    icon_center="$ICON_PAUSE"
    color="$TEXT"
    ;;
  Paused)
    icon_center="$ICON_PLAY"
    color="$MUTED"
    ;;
  *)
    icon_center="$ICON_PLAY"
    color="$OFF"
    ;;
esac

# =========================
# Output
# =========================
printf "<span color='%s'>%s</span>  <span color='%s'>%s</span>  <span color='%s'>%s</span>\n" \
  "$MUTED" "$ICON_PREV" \
  "$color" "$icon_center" \
  "$MUTED" "$ICON_NEXT"