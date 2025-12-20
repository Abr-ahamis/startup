#!/usr/bin/env bash
# Network block that reads GNOME-exporter network rates from JSON if available
JSON=/tmp/gnome_status.json
SAMPLE=0.4  # sub-second responsiveness

human_rate() {
  local bps=$1
  if [[ -z "$bps" ]]; then echo "0 B/s"; return; fi
  # use awk formatting like your example
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

while true; do
  if [[ -r "$JSON" ]]; then
    # If the exporter already computes down_bps/up_bps, use them:
    down=$(jq -r '.network.down_bps // empty' "$JSON" 2>/dev/null)
    up=$(jq -r '.network.up_bps // empty' "$JSON" 2>/dev/null)
    if [[ -n "$down" && -n "$up" ]]; then
      DOWN=$(human_rate "$down")
      UP=$(human_rate "$up")
      IF=$(jq -r '.network.ifname // "?"' "$JSON" 2>/dev/null)
      IP=$(jq -r '.network.ip // "-" ' "$JSON" 2>/dev/null)
      echo "↑ $UP    ↓ $DOWN    |    $IP   ($IF)"
      echo ""
      sleep "$SAMPLE"
      continue
    fi
  fi

  # Fallback: compute local deltas using /sys/class/net for first suitable iface
  # pick iface (wlan0, eth0, or first global IPv4)
  IFACE=$(ip -o -4 addr show scope global | awk '{print $2; exit}')
  [[ -z "$IFACE" ]] && { echo "No net"; echo ""; sleep "$SAMPLE"; continue; }

  RX1=$(cat /sys/class/net/"$IFACE"/statistics/rx_bytes 2>/dev/null || echo 0)
  TX1=$(cat /sys/class/net/"$IFACE"/statistics/tx_bytes 2>/dev/null || echo 0)
  sleep 0.4
  RX2=$(cat /sys/class/net/"$IFACE"/statistics/rx_bytes 2>/dev/null || echo 0)
  TX2=$(cat /sys/class/net/"$IFACE"/statistics/tx_bytes 2>/dev/null || echo 0)

  rx_delta=$((RX2 - RX1))
  tx_delta=$((TX2 - TX1))
  elapsed=0.4
  RX_BPS=$((rx_delta / elapsed))
  TX_BPS=$((tx_delta / elapsed))
  DOWN=$(human_rate "$RX_BPS")
  UP=$(human_rate "$TX_BPS")
  IP=$(ip -4 addr show dev "$IFACE" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)
  echo "↑ $UP    ↓ $DOWN    |    $IP   ($IFACE)"
  echo ""
  sleep "$SAMPLE"
done
