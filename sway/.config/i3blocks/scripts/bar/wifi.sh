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
ICON_COLOR="#89dceb"

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    foot -e bash -ic 'exec "$HOME/.config/i3blocks/scripts/menu/wifi_menu.sh"' >/dev/null 2>&1 &
    ;;
esac

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_WIFI=""
ICON_DOT="●"

# =========================
# Logic
# =========================
radio="$(nmcli radio wifi 2>/dev/null || printf disabled)"

if [ "$radio" != "enabled" ]; then
  dot_color="$CRITICAL"
  label="off"
else
  ssid="$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes" {print $2; exit}')"

  if [ -n "$ssid" ]; then
    dot_color="$HEALTHY"
    label="${ssid:0:6}"
  else
    dot_color="$CRITICAL"
    label="---"
  fi
fi

# =========================
# Output
# =========================
printf "| <span color='%s'>%s </span><span color='%s'>%s</span> \n" \
  "$NETWORK" "$ICON_DOT" "$dot_color" "$label"
