#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
TEXT="#ffffff"
ICON_COLOR="#74c7ec"
GLOBE_COLOR="#ffffff"
LOCAL_COLOR="#ffffff"
NO_IP_COLOR="#ffffff"

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    foot -e bash -ic 'exec "$HOME/.config/i3blocks/scripts/menu/ip_menu.sh"' >/dev/null 2>&1 &
    ;;
esac

# =========================
# Icons
# =========================
ICON_GLOBE=""
ICON_NO_IP=""
ICON_LOCAL=""

# =========================
# Public IP
# =========================
public_ip="$(
  command -v curl >/dev/null 2>&1 && \
  curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true
)"

# =========================
# Local IP
# =========================
get_ip_for_iface() {
  local iface="$1"
  ip -4 -o addr show dev "$iface" scope global 2>/dev/null | \
    awk '{split($4,a,"/"); print a[1]; exit}'
}

local_ip="$(
  command -v ip >/dev/null 2>&1 && {
    for iface in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(tun|tap|wg|vpn|tailscale|zt|ppp)[0-9a-zA-Z_-]*$' | sort -u); do
      ipaddr="$(get_ip_for_iface "$iface")"
      [ -n "${ipaddr:-}" ] && { printf '%s' "$ipaddr"; break; }
    done

    [ -n "${ipaddr:-}" ] || for iface in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(eth|en)[0-9a-zA-Z_-]*$' | sort -u); do
      ipaddr="$(get_ip_for_iface "$iface")"
      [ -n "${ipaddr:-}" ] && { printf '%s' "$ipaddr"; break; }
    done

    [ -n "${ipaddr:-}" ] || for iface in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^(wlan|wl)[0-9a-zA-Z_-]*$' | sort -u); do
      ipaddr="$(get_ip_for_iface "$iface")"
      [ -n "${ipaddr:-}" ] && { printf '%s' "$ipaddr"; break; }
    done
  } || true
)"

# =========================
# Output
# =========================
if [ -z "${public_ip:-}" ]; then
  public_part="<span color='$ICON_COLOR'>$ICON_NO_IP </span><span color='$TEXT'>no public ip</span>"
else
  public_part="<span color='$ICON_COLOR'>$ICON_GLOBE </span><span color='$TEXT'>$public_ip</span>"
fi

if [ -z "${local_ip:-}" ]; then
  local_part="<span color='$ICON_COLOR'>$ICON_NO_IP </span><span color='$TEXT'>no local ip</span>"
else
  local_part="<span color='$ICON_COLOR'>$ICON_LOCAL </span><span color='$TEXT'>$local_ip</span>"
fi

printf " | %s | %s\n" "$public_part" "$local_part"
