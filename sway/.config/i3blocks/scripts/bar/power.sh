#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
BLUE="#0088cc"

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    foot bash -c "sudo \"$HOME/.config/i3blocks/scripts/menu/power_menu.sh\"; exec bash" >/dev/null 2>&1 &
    ;;
esac

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_POWER=" ⏻  "

# =========================
# Output
# =========================
printf "<span color='%s'>%s</span>\n" "$BLUE" "$ICON_POWER"
