#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
TEXT="#c9d1d9"

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_CLIPBOARD=""

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    if command -v greenclip >/dev/null 2>&1; then
      greenclip print | rofi -dmenu -i -p clipboard -theme "$HOME/.config/rofi/themes/dark.rasi" | wl-copy
    fi >/dev/null 2>&1 &
    ;;
  3)
    greenclip clear >/dev/null 2>&1 || true
    ;;
esac

# =========================
# Output
# =========================
printf "<span color='%s'>| %s</span>\n" "$TEXT" "$ICON_CLIPBOARD"