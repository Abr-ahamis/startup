#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
BLUE="#0088cc"

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_POWER="⏻"

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    nohup "$HOME/.config/sway/scripts/power_menu.sh" >/dev/null 2>&1 &
    ;;
esac

# =========================
# Output
# =========================
printf "<span color='%s'>| %s</span>\n" "$BLUE" "$ICON_POWER"