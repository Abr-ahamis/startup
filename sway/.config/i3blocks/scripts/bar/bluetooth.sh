#!/usr/bin/env bash
set -u
source "$(dirname "$0")/colors.sh"

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
  dot_color="$ACCENT"
else
  dot_color="$ATTENTION"
fi

# =========================
# Output
# =========================
printf "|<span color='%s'> %s </span><span color='%s'>%s</span> \n" \
  "$dot_color" "$ICON_DOT" "$PRIMARY_TEXT" "$ICON_BLUETOOTH"
