#!/usr/bin/env bash

# File to store the last state
STATE_FILE="/tmp/i3blocks_net_speed.state"

# --- Functions ---

# Human-readable bytes/sec
human_rate() {
  local bps="$1"
  if [[ -z "$bps" || "$bps" -lt 0 ]]; then
    bps=0
  fi
  awk -v bps="$bps" 'BEGIN{
    if (bps < 1000) {
      printf("%.0f B/s", bps)
    } else if (bps < 1000*1000) {
      printf("%.1f K/s", bps/1000)
    } else if (bps < 1000*1000*1000) {
      printf("%.2f M/s", bps/(1000*1000))
    } else {
      printf("%.2f G/s", bps/(1000*1000*1000))
    }
  }'
}

# Pick the primary network interface
pick_iface() {
  ip route | grep '^default' | awk '{print $5}' | head -n1
}

# Read RX/TX counters for a given interface
read_counter() {
  local iface="$1" which="$2"
  local path="/sys/class/net/${iface}/statistics/${which}_bytes"
  [[ -r "$path" ]] && cat "$path" || echo 0
}

# Get IP address for a given interface
get_ip() {
  local iface="$1"
  ip -4 addr show dev "$iface" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1
}

# --- Main Logic ---

IFACE=$(pick_iface)
if [ -z "$IFACE" ]; then
  echo "No net"
  exit 0
fi

# Get current byte counts and time
time_now=$(date +%s.%N)
rx_now=$(read_counter "$IFACE" rx)
tx_now=$(read_counter "$IFACE" tx)

# Read previous state if it exists
if [ -r "$STATE_FILE" ]; then
  read -r time_prev rx_prev tx_prev < "$STATE_FILE"
else
  # If no previous state, we can't calculate speed yet.
  # Prime the state file for the next run.
  echo "$time_now $rx_now $tx_now" > "$STATE_FILE"
  echo "↑ ... K/s    ↓ ... K/s"
  exit 0
fi

# Calculate time and data deltas
time_delta=$(awk "BEGIN{print $time_now - $time_prev}")
rx_delta=$(($rx_now - $rx_prev))
tx_delta=$(($tx_now - $tx_prev))

# Avoid division by zero if the script is called too quickly
if (( $(echo "$time_delta < 0.001" | bc -l) )); then
    time_delta=1
fi

# Calculate speeds in bytes per second
rx_bps=$(awk "BEGIN{print $rx_delta / $time_delta}")
tx_bps=$(awk "BEGIN{print $tx_delta / $time_delta}")

# Store the current state for the next run
echo "$time_now $rx_now $tx_now" > "$STATE_FILE"

# Format for output
DOWN=$(human_rate "$rx_bps")
UP=$(human_rate "$tx_bps")
IP=$(get_ip "$IFACE")

# --- Output for i3blocks ---
# Example: ↑ 1.2 M/s    ↓ 25.4 K/s    |    192.168.1.100   (wlan0)
echo "↑ $UP    ↓ $DOWN    |    $IP   ($IFACE)"
