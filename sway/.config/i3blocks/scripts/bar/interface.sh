#!/usr/bin/env bash
set -u
source "$(dirname "$0")/colors.sh"

# =========================
# Config
# =========================
MUTED="#ffffff"
ICON_COLOR="#89dceb"
TEXT="#ffffff"

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    foot -e "$HOME/.config/i3blocks/scripts/menu/wifi_menu.sh" >/dev/null 2>&1 &
    ;;
esac

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_VPN="󰌘"
ICON_WIFI=""
ICON_ETH=""
ICON_UNKNOWN=""

# =========================
# Logic
# =========================
get_ip_for_iface() {
  local iface="$1"
  ip -4 -o addr show dev "$iface" scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]; exit}'
}

iface=""
icon="$ICON_UNKNOWN"
icon_color="$DISABLED"

for i in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(tun|tap|wg|vpn|tailscale|zt|ppp)[0-9a-zA-Z_-]*$' | sort -u); do
  if [ -n "$(get_ip_for_iface "$i")" ]; then
    iface="$i"
    icon="$ICON_VPN"
    icon_color='#5E5CE6'
    break
  fi
done

if [ -z "$iface" ]; then
  for i in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(eth|en)[0-9a-zA-Z_-]*$' | sort -u); do
    if [ -n "$(get_ip_for_iface "$i")" ]; then
      iface="$i"
      icon="$ICON_ETH"
      icon_color="$ACCENT"
      break
    fi
  done
fi

if [ -z "$iface" ]; then
  for i in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(wl|wlan)[0-9a-zA-Z_-]*$' | sort -u); do
    if [ -n "$(get_ip_for_iface "$i")" ]; then
      iface="$i"
      icon="$ICON_WIFI"
      icon_color="$NETWORK"
      break
    fi
  done
fi

[ -z "$iface" ] && iface="---"

# =========================
# Output
# =========================
printf "| <span color='%s'>%s </span> <span color='%s'>%s</span> \n" \
  "$icon_color" "$icon" "$PRIMARY_TEXT" "$iface"
