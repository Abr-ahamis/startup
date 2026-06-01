#!/usr/bin/env bash
set -u

TEXT="#c9d1d9"

signal_bar() {
  pkill -RTMIN+11 i3blocks 2>/dev/null || true
}

case "${BLOCK_BUTTON:-}" in
  1) nohup "$HOME/.config/sway/scripts/brightness_menu.sh" >/dev/null 2>&1 & ;;
  4) brightnessctl set 5%+ 2>/dev/null; signal_bar ;;
  5) brightnessctl set 5%- 2>/dev/null; signal_bar ;;
esac

current="$(brightnessctl get 2>/dev/null || printf 0)"
max="$(brightnessctl max 2>/dev/null || printf 1)"
[ "$max" -le 0 ] && max=1
pct=$((100 * current / max))

icon=$'\uf185'

printf "<span color='%s'>%s</span>\n" "$TEXT" "| $icon"
