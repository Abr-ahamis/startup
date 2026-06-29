#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
OFF="#4a5568"
IDLE="#c98a2d"
ON="#3d8f5a"
TEXT="#c9d1d9"

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    foot bash -c "sudo \"$HOME/.config/i3blocks/scripts/menu/bt_menu.sh\"; exec bash" >/dev/null 2>&1 &
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
  dot_color="$OFF"
else
  mac="$(timeout 2 bluetoothctl devices Connected 2>/dev/null | awk 'NR==1 {print $2}')"
  if [ -n "$mac" ]; then
    dot_color="$ON"
  else
    dot_color="$IDLE"
  fi
fi

# =========================
# Output
# =========================
printf "|<span color='%s'> %s </span><span color='%s'>%s</span>\n" \
  "$dot_color" "$ICON_DOT" "$TEXT" "$ICON_BLUETOOTH"