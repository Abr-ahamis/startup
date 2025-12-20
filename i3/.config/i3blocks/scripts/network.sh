#!/usr/bin/env bash
SAMPLE_SECS="${SAMPLE_SECS:-0.6}"   # seconds between samples
SMOOTH_ALPHA="${SMOOTH_ALPHA:-0.35}" # smoothing factor [0..1], higher = more responsive
ONCE=1   # i3blocks expects a single output, so we'll run one sample per execution

# human-readable bytes/sec
human_rate() {
  local bps="$1"
  awk -v bps="$bps" 'BEGIN{
    if (bps < 0) bps = 0
    if (bps < 1000) {
      printf("%.0f B/s", bps)
    } else if (bps < 1000*1000) {
      printf("%.0f KB/s", bps/1000)
    } else if (bps < 1000*1000*1000) {
      printf("%.1f MB/s", bps/(1000*1000))
    } else {
      printf("%.1f GB/s", bps/(1000*1000*1000))
    }
  }'
}

# pick interface
pick_iface() {
  local tun_if
  tun_if=$(ip -o -4 addr show | awk '$2 ~ /^tun|^tap/ {print $2; exit}')
  [[ -n "$tun_if" ]] && { printf '%s' "$tun_if"; return 0; }

  if ip -o -4 addr show dev wlan0 >/dev/null 2>&1; then
    printf 'wlan0'
    return 0
  fi

  local any_if
  any_if=$(ip -o -4 addr show scope global | awk '{print $2; exit}')
  [[ -n "$any_if" ]] && { printf '%s' "$any_if"; return 0; }
  return 1
}

# read counter
read_counter() {
  local iface="$1" which="$2"
  local path="/sys/class/net/${iface}/statistics/${which}_bytes"
  [[ -r "$path" ]] && cat "$path" 2>/dev/null || echo 0
}

# get IP
get_ip() {
  local iface="$1"
  ip -4 addr show dev "$iface" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1
}

# --- main ---
IFACE=$(pick_iface) || IFACE=""
[ -z "$IFACE" ] && { echo "No net"; exit 0; }

RX1=$(read_counter "$IFACE" rx)
TX1=$(read_counter "$IFACE" tx)
sleep "$SAMPLE_SECS"
RX2=$(read_counter "$IFACE" rx)
TX2=$(read_counter "$IFACE" tx)

elapsed=$(awk -v t1="$RX1" -v t2="$RX2" -v s="$SAMPLE_SECS" 'BEGIN{printf "%.6f", s}')
rx_delta=$((RX2 - RX1))
tx_delta=$((TX2 - TX1))

# smoothing
sm_rx=$(awk -v s="$SMOOTH_ALPHA" -v prev="$rx_delta" -v cur="$rx_delta" 'BEGIN{printf "%.6f", s*cur + (1-s)*prev}')
sm_tx=$(awk -v s="$SMOOTH_ALPHA" -v prev="$tx_delta" -v cur="$tx_delta" 'BEGIN{printf "%.6f", s*cur + (1-s)*prev}')

RX_BPS=$(awk -v d="$sm_rx" -v e="$elapsed" 'BEGIN{printf "%.0f", d / e}')
TX_BPS=$(awk -v d="$sm_tx" -v e="$elapsed" 'BEGIN{printf "%.0f", d / e}')

DOWN=$(human_rate "$RX_BPS")
UP=$(human_rate "$TX_BPS")
IP=$(get_ip "$IFACE")

# --- output for i3blocks ---
echo "↑ $UP    ↓ $DOWN    |    $IP   ($IFACE)"
