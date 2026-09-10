#!/usr/bin/env bash
set -uo pipefail

if command -v wofi >/dev/null 2>&1; then
  options="Shutdown
Restart
Sleep
Logout
Cancel"

  choice="$(printf '%s\n' "$options" | wofi --dmenu --insensitive --prompt power 2>/dev/null || true)"

  case "$choice" in
    Shutdown)
      command -v systemctl >/dev/null 2>&1 && systemctl poweroff || { command -v notify-send >/dev/null 2>&1 && notify-send 'Power menu' 'systemctl is unavailable'; }
      ;;
    Restart)
      command -v systemctl >/dev/null 2>&1 && systemctl reboot || { command -v notify-send >/dev/null 2>&1 && notify-send 'Power menu' 'systemctl is unavailable'; }
      ;;
    Sleep)
      command -v systemctl >/dev/null 2>&1 && systemctl suspend || { command -v notify-send >/dev/null 2>&1 && notify-send 'Power menu' 'systemctl is unavailable'; }
      ;;
    Logout)
      swaymsg exit
      ;;
    ""|Cancel)
      exit 0
      ;;
  esac
else
  echo "wofi not installed"
fi
