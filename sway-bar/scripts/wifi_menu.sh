#!/usr/bin/env bash
set -u

theme="$HOME/.config/rofi/themes/dark.rasi"
choice="$(printf "Scan\nToggle WiFi\nOpen Connections\n" | rofi -dmenu -i -p network -theme "$theme")"
case "$choice" in
  Scan)
    nmcli dev wifi rescan >/dev/null 2>&1 || true
    nmcli -t -f ssid,signal,security dev wifi list 2>/dev/null |
      awk -F: 'NF {printf "%s  %s%%  %s\n", ($1?$1:"hidden"), $2, $3}' |
      rofi -dmenu -i -p ssid -theme "$theme" |
      awk '{print $1}' |
      xargs -r nmcli dev wifi connect
    ;;
  "Toggle WiFi")
    if [ "$(nmcli radio wifi 2>/dev/null)" = "enabled" ]; then nmcli radio wifi off; else nmcli radio wifi on; fi
    ;;
  "Open Connections")
    nohup nm-connection-editor >/dev/null 2>&1 &
    ;;
esac
