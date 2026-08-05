#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
TEXT="#ffffff"
ICON_COLOR="#f9e2af"

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    foot -e "$HOME/.config/i3blocks/scripts/menu/vol-brigh_menu.sh" >/dev/null 2>&1 &
    ;;
esac

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_BRIGHTNESS=""

# =========================
# Helpers
# =========================
signal_bar() {
  pkill -RTMIN+11 i3blocks 2>/dev/null || true
}

# =========================
# Logic
# =========================
current="$(brightnessctl get 2>/dev/null || printf 0)"
max="$(brightnessctl max 2>/dev/null || printf 1)"

[ "$max" -le 0 ] && max=1

pct=$((100 * current / max))

# =========================
# Output
# =========================
printf "|<span color='%s'> %s %s%%</span>\n" \
  "$ICON_COLOR" "$ICON_BRIGHTNESS" "$pct"
