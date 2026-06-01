#!/usr/bin/env bash
set -u

MUTED="#6e7681"
TEXT="#c9d1d9"

iface="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
if [ -z "${iface}" ] || [ ! -r "/sys/class/net/${iface}/statistics/tx_bytes" ]; then
  printf "<span color='%s'>↑0B  ↓0B</span>\n" "$MUTED"
  exit 0
fi

now="$(date +%s)"
tx="$(cat "/sys/class/net/${iface}/statistics/tx_bytes")"
rx="$(cat "/sys/class/net/${iface}/statistics/rx_bytes")"
state_dir="${XDG_RUNTIME_DIR:-/tmp}"
state="${state_dir}/i3blocks_netspeed_${iface}_${UID:-$(id -u)}"

prev_now="$now"
prev_tx="$tx"
prev_rx="$rx"
[ -r "$state" ] && read -r prev_now prev_tx prev_rx < "$state"
printf "%s %s %s\n" "$now" "$tx" "$rx" > "$state" 2>/dev/null || true

delta=$((now - prev_now))
[ "$delta" -le 0 ] && delta=1
tx_rate=$(((tx - prev_tx) / delta))
rx_rate=$(((rx - prev_rx) / delta))
[ "$tx_rate" -lt 0 ] && tx_rate=0
[ "$rx_rate" -lt 0 ] && rx_rate=0

fmt_rate() {
  local b="$1"
  if [ "$b" -ge 1048576 ]; then awk -v n="$b" 'BEGIN {printf "%.1fM", n/1048576}'
  elif [ "$b" -ge 1024 ]; then awk -v n="$b" 'BEGIN {printf "%.0fK", n/1024}'
  else printf "%sB" "$b"
  fi
}

printf "<span color='%s'>↑</span><span color='%s'>%s</span><span color='%s'>  ↓</span><span color='%s'>%s</span>\n" \
  "$MUTED" "$TEXT" "$(fmt_rate "$tx_rate")" "$MUTED" "$TEXT" "$(fmt_rate "$rx_rate")"
