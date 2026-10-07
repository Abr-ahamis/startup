#!/usr/bin/env bash
set -u
source "$(dirname "$0")/colors.sh"

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
      cliphist list | "$HOME/.local/bin/wofi-popup.sh" --dmenu --insensitive --prompt clipboard --width 620 --height 820 | cliphist decode | wl-copy
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
printf "<span color='%s'>|</span> <span color='%s'>%s</span> \n" "$PRIMARY_TEXT" "$STABLE_ICON" "$ICON_CLIPBOARD"
