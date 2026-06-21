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
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_WIFI=""
ICON_DOT="●"

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    nohup "$HOME/.config/sway/scripts/wifi_menu.sh" >/dev/null 2>&1 &
    ;;
  3)
    nohup nm-connection-editor >/dev/null 2>&1 &
    ;;
esac

# =========================
# Logic
# =========================
radio="$(nmcli radio wifi 2>/dev/null || printf disabled)"

if [ "$radio" != "enabled" ]; then
  dot_color="$OFF"
  label="off"
else
  ssid="$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes" {print $2; exit}')"

  if [ -n "$ssid" ]; then
    dot_color="$ON"
    label="${ssid:0:6}"
  else
    dot_color="$IDLE"
    label="---"
  fi
fi

# =========================
# Output
# =========================
printf "| <span color='%s'>%s </span><span color='%s'>%s</span>\n" \
  "$dot_color" "$ICON_DOT" "$TEXT" "$label"