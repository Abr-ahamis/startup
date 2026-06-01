#!/usr/bin/env bash
set -u

OFF="#4a5568"
IDLE="#c98a2d"
ON="#3d8f5a"
TEXT="#c9d1d9"

case "${BLOCK_BUTTON:-}" in
  1) nohup "$HOME/.config/sway/scripts/wifi_menu.sh" >/dev/null 2>&1 & ;;
  3) nohup nm-connection-editor >/dev/null 2>&1 & ;;
esac

radio="$(nmcli radio wifi 2>/dev/null || printf disabled)"
if [ "$radio" != "enabled" ]; then
  dot="$OFF"; label="off"
else
  ssid="$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes" {print $2; exit}')"
  if [ -n "$ssid" ]; then
    dot="$ON"; label="${ssid:0:6}"
  else
    dot="$IDLE"; label="---"
  fi
fi

printf "| <span color='%s'>● </span><span color='%s'>%s</span>\n" "$dot" "$TEXT" "$label"
