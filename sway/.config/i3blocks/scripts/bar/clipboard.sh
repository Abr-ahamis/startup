#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
TEXT="#c9d1d9"

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    if command -v greenclip >/dev/null 2>&1; then
      greenclip print | rofi -dmenu -i -p clipboard | wl-copy
    fi >/dev/null 2>&1 &
    ;;
  3)
    greenclip clear >/dev/null 2>&1 || true
    ;;
esac

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_CLIPBOARD=""

# =========================
# Output
# =========================
printf "<span color='%s'>| %s</span>\n" "$TEXT" "$ICON_CLIPBOARD"