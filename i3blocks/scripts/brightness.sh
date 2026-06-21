#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
TEXT="#c9d1d9"

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
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    nohup "$HOME/.config/sway/scripts/brightness_menu.sh" >/dev/null 2>&1 &
    ;;
  4)
    brightnessctl set 5%+ 2>/dev/null
    signal_bar
    ;;
  5)
    brightnessctl set 5%- 2>/dev/null
    signal_bar
    ;;
esac

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
printf "<span color='%s'>| %s %s%%</span>\n" \
  "$TEXT" "$ICON_BRIGHTNESS" "$pct"