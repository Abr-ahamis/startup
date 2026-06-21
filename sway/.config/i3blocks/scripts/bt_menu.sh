#!/usr/bin/env bash
set -u

theme="$HOME/.config/rofi/themes/dark.rasi"
choice="$(printf "Power Toggle\nScan On\nScan Off\nOpen Manager\n" | rofi -dmenu -i -p bluetooth -theme "$theme")"
case "$choice" in
  "Power Toggle")
    if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then bluetoothctl power off; else bluetoothctl power on; fi
    ;;
  "Scan On") bluetoothctl scan on ;;
  "Scan Off") bluetoothctl scan off ;;
  "Open Manager") nohup blueman-manager >/dev/null 2>&1 & ;;
esac
