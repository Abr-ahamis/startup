#!/usr/bin/env bash
set -u

theme="$HOME/.config/rofi/themes/dark.rasi"
choice="$(printf "Brightness 25%%\nBrightness 50%%\nBrightness 75%%\nBrightness 100%%\n" | rofi -dmenu -i -p brightness -theme "$theme")"
case "$choice" in
  "Brightness 25%") brightnessctl set 25% ;;
  "Brightness 50%") brightnessctl set 50% ;;
  "Brightness 75%") brightnessctl set 75% ;;
  "Brightness 100%") brightnessctl set 100% ;;
esac
pkill -RTMIN+11 i3blocks 2>/dev/null || true
