#!/usr/bin/env bash
set -u
source "$(dirname "$0")/colors.sh"

# =========================
# Config
# =========================
BLUE="#f38ba8"

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    "$HOME/.config/sway/scripts/power-menu.sh" >/dev/null 2>&1 &
    ;;
esac

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_POWER=" ⏻ "

# =========================
# Output
# =========================
printf "<span color='%s'>%s</span>\n" "$CRITICAL" "$ICON_POWER"
