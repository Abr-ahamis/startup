#!/usr/bin/env bash
set -euo pipefail

slot="${1:-}"
[[ "$slot" =~ ^[12]$ ]] || exit 2
mapfile -t network_ifaces < <(nmcli -t --escape yes -f DEVICE,TYPE,STATE device status 2>/dev/null | awk -F: '($2=="wifi" || $2=="ethernet") && $3!="unavailable" && $3!="unmanaged" {print $1 ":" $2}')
entry="${network_ifaces[$((slot - 1))]:-}"
[[ -n "$entry" ]] || exit 0
iface="${entry%%:*}"
iface_type="${entry#*:}"

if [[ "$iface_type" == wifi ]]; then
  foot -T "Wi-Fi: $iface" -e bash -ic 'exec "$HOME/.config/i3blocks/scripts/menu/wifi_menu.sh" --preferred-interface "$1"' wifi-menu "$iface" >/dev/null 2>&1 &
else
  foot -T "Network: $iface" -e bash -ic 'exec bash "$HOME/.config/i3blocks/scripts/menu/network_interface_menu.sh" "$1"' network-menu "$iface" >/dev/null 2>&1 &
fi
