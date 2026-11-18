#!/usr/bin/env bash
set -u
source "$(dirname "$0")/colors.sh"

# =========================
# Config
# =========================
MUTED="#ffffff"
TEXT="#ffffff"
ICON_COLOR="#89b4fa"

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
ICON_UP=""
ICON_DOWN=""

# =========================
# Helpers
# =========================
fmt_rate() {
  local b="$1"
  if [ "$b" -ge 1048576 ]; then
    local tenths=$((b * 10 / 1048576))
    printf '%d.%dM' "$((tenths / 10))" "$((tenths % 10))"
  elif [ "$b" -ge 1024 ]; then
    printf '%dK' "$((b / 1024))"
  else
    printf "%sB" "$b"
  fi
}

# =========================
# Logic
# =========================
route="$(ip -o route get 1.1.1.1 2>/dev/null || true)"
read -r -a route_fields <<<"$route"
iface=""
for ((i = 0; i + 1 < ${#route_fields[@]}; i++)); do
  if [[ "${route_fields[i]}" == dev ]]; then
    iface="${route_fields[i + 1]}"
    break
  fi
done

if [ -z "${iface}" ] || [ ! -r "/sys/class/net/${iface}/statistics/tx_bytes" ]; then
  printf "<span color='%s'>%s</span> <span color='%s'>0B</span>  <span color='%s'>%s</span> <span color='%s'>0B</span>\n" \
    '#5E5CE6' "$ICON_UP" "$PRIMARY_TEXT" "$ACCENT" "$ICON_DOWN" "$PRIMARY_TEXT"
  exit 0
fi

read -r uptime _ </proc/uptime
uptime_seconds="${uptime%%.*}"
uptime_fraction="${uptime#*.}00"
uptime_fraction="${uptime_fraction:0:2}"
now_cs=$((10#$uptime_seconds * 100 + 10#$uptime_fraction))
IFS= read -r tx <"/sys/class/net/${iface}/statistics/tx_bytes"
IFS= read -r rx <"/sys/class/net/${iface}/statistics/rx_bytes"

state_dir="${XDG_RUNTIME_DIR:-/tmp}"
state="${state_dir}/i3blocks_netspeed_cs_${iface}_${UID:-$(id -u)}"

prev_now="$now_cs"
prev_tx="$tx"
prev_rx="$rx"

if [ -r "$state" ]; then
  read -r prev_now prev_tx prev_rx < "$state"
fi

printf "%s %s %s\n" "$now_cs" "$tx" "$rx" > "$state" 2>/dev/null || true

delta_cs=$((now_cs - prev_now))
[ "$delta_cs" -le 0 ] && delta_cs=70

tx_delta=$((tx - prev_tx))
rx_delta=$((rx - prev_rx))
[ "$tx_delta" -lt 0 ] && tx_delta=0
[ "$rx_delta" -lt 0 ] && rx_delta=0
tx_rate=$((tx_delta * 100 / delta_cs))
rx_rate=$((rx_delta * 100 / delta_cs))

# =========================
# Output
# =========================
printf "<span color='%s'>%s</span> <span color='%s'>%s</span> <span color='%s'>| %s</span> <span color='%s'>%s</span>\n" \
  '#5E5CE6' "$ICON_UP" "$PRIMARY_TEXT" "$(fmt_rate "$tx_rate")" \
  "$ACCENT" "$ICON_DOWN" "$PRIMARY_TEXT" "$(fmt_rate "$rx_rate")"
