#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
TEXT="#ffffff"
ICON_COLOR="#cba6f7"

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    if command -v cliphist >/dev/null 2>&1; then
      cliphist list | wofi --dmenu --insensitive --prompt clipboard | cliphist decode | wl-copy
    fi >/dev/null 2>&1 &
    ;;
  3)
    command -v cliphist >/dev/null 2>&1 && cliphist wipe >/dev/null 2>&1 || true
    ;;
esac

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_CLIPBOARD=""

# =========================
# Output
# =========================
printf "<span color='%s'>| %s</span> \n" "$ICON_COLOR" "$ICON_CLIPBOARD"
