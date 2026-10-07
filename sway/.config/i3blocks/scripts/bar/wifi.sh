#!/usr/bin/env bash
set -u
source "$(dirname "$0")/colors.sh"

slot="${BLOCK_INSTANCE:-1}"
[[ "$slot" =~ ^[12]$ ]] || slot=1
mapfile -t network_ifaces < <(nmcli -t --escape yes -f DEVICE,TYPE,STATE device status 2>/dev/null | awk -F: '($2=="wifi" || $2=="ethernet") && $3!="unavailable" && $3!="unmanaged" {print $1 ":" $2}')
entry="${network_ifaces[$((slot - 1))]:-}"
[[ -n "$entry" ]] || exit 0
iface="${entry%%:*}"
iface_type="${entry#*:}"
radio="$(nmcli radio wifi 2>/dev/null || printf disabled)"
if [[ "$iface_type" == wifi ]]; then ICON=""; else ICON=""; fi

if [[ "${BLOCK_BUTTON:-}" == 1 ]]; then
  "$HOME/.config/i3blocks/scripts/bar/wifi_click.sh" "$slot" >/dev/null 2>&1 &
fi

state="$(nmcli -g GENERAL.STATE device show "$iface" 2>/dev/null || true)"
profile="$(nmcli -g GENERAL.CONNECTION device show "$iface" 2>/dev/null || true)"
connection="--"
if [[ "$state" == '100 (connected)' && -n "$profile" && "$profile" != -- ]]; then
  if [[ "$iface_type" == wifi ]]; then
    connection="$(nmcli -g 802-11-wireless.ssid connection show "$profile" 2>/dev/null || true)"
  else
    connection="$profile"
  fi
  [[ -n "$connection" ]] || connection='--'
fi
[[ "$radio" == enabled || "$iface_type" != wifi ]] || connection='off'
label="$iface | $connection"

printf "| <span color='%s'>%s </span><span color='%s'>%s</span> \n" \
  "$NETWORK" "$ICON" "$PRIMARY_TEXT" "$label"
