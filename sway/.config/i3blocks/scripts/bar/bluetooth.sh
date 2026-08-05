#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
OFF="#ffffff"
IDLE="#ffffff"
ON="#ffffff"
TEXT="#ffffff"
ICON_COLOR="#ffffff"
BLUETOOTH_COLOR="#89b4fa"

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    foot -e "$HOME/.config/i3blocks/scripts/menu/bt_menu.sh" >/dev/null 2>&1 &
    ;;
  3)
    nohup blueman-manager >/dev/null 2>&1 &
    ;;
esac

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_BLUETOOTH=""
ICON_DOT="●"

# =========================
# Logic
# =========================
powered="$(timeout 2 bluetoothctl show 2>/dev/null | awk -F': ' '/Powered:/ {print $2; exit}')"

if [ "$powered" != "yes" ]; then
  dot_color="$TEXT"
else
  mac="$(timeout 2 bluetoothctl devices Connected 2>/dev/null | awk 'NR==1 {print $2}')"
  if [ -n "$mac" ]; then
    dot_color="$TEXT"
  else
    dot_color="$TEXT"
  fi
fi

# =========================
# Output
# =========================
printf "|<span color='%s'> %s </span><span color='%s'>%s</span> \n" \
  "$TEXT" "$ICON_DOT" "$BLUETOOTH_COLOR" "$ICON_BLUETOOTH"
