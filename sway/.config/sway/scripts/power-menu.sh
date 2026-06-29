#!/usr/bin/env bash
set -euo pipefail

if command -v rofi >/dev/null 2>&1; then
  options="Shutdown
Restart
Logout
Cancel"
  choice="$(printf '%s
' "$options" | rofi -dmenu -i -p power)"
  case "$choice" in
    Shutdown)
      systemctl poweroff
      ;;
    Restart)
      systemctl reboot
      ;;
    Logout)
      swaymsg exit
      ;;
    ""|Cancel)
      exit 0
      ;;
  esac
else
  echo "rofi not installed"
fi
