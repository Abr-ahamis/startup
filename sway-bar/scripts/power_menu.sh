#!/usr/bin/env bash
set -u

theme="$HOME/.config/rofi/themes/dark.rasi"
choice="$(printf "Lock\nSuspend\nLogout\nReboot\nShutdown\n" | rofi -dmenu -i -p session -theme "$theme")"
case "$choice" in
  Lock) swaylock -c 0e1117 ;;
  Suspend) systemctl suspend ;;
  Logout) swaymsg exit ;;
  Reboot) systemctl reboot ;;
  Shutdown) systemctl poweroff ;;
esac
