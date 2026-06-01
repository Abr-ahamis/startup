#!/usr/bin/env bash
set -u

OFF="#4a5568"
IDLE="#c98a2d"
ON="#3d8f5a"
TEXT="#c9d1d9"
ICON=$'\uf294'

case "${BLOCK_BUTTON:-}" in
  1) nohup "$HOME/.config/sway/scripts/bt_menu.sh" >/dev/null 2>&1 & ;;
  3) nohup blueman-manager >/dev/null 2>&1 & ;;
esac

powered="$(timeout 2 bluetoothctl show 2>/dev/null | awk -F': ' '/Powered:/ {print $2; exit}')"
if [ "$powered" != "yes" ]; then
  dot="$OFF"
else
  mac="$(timeout 2 bluetoothctl devices Connected 2>/dev/null | awk 'NR==1 {print $2}')"
  if [ -n "$mac" ]; then
    dot="$ON"
  else
    dot="$IDLE"
  fi
fi

printf "|<span color='%s'> ● </span><span color='%s'>%s</span>\n" "$dot" "$TEXT" "$ICON"
