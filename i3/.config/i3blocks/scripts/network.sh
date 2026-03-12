#!/usr/bin/env bash
# Persistent high-precision network speed monitor for i3blocks
# Defaults: INTERVAL=0.1 (100ms). Use --debug to run in terminal for troubleshooting.
set -uo pipefail

INTERVAL=0.1            # seconds (fractional allowed). Change this to 0.05/0.2 etc
SMOOTH_ALPHA=0.25       # EMA smoothing factor (0..1). Lower = smoother/laggier.

# CLI flags
DEBUG=false
ENSURE_DEPS=false
for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=true ;;
    --ensure-deps) ENSURE_DEPS=true ;;
    --interval=*) INTERVAL="${arg#--interval=}" ;;
  esac
done

# --- Helpers ---
human_rate() {
  # input bytes/sec (may be float)
  awk -v bps="$1" 'BEGIN{
    if (bps == "" || bps < 0) bps = 0;
    if (bps < 1000) { printf("%.0f B/s", bps); }
    else if (bps < 1000*1000) { printf("%.1f K/s", bps/1000); }
    else if (bps < 1000*1000*1000) { printf("%.2f M/s", bps/(1000*1000)); }
    else { printf("%.2f G/s", bps/(1000*1000*1000)); }
  }'
}

# unsigned diff (handles 64-bit wrap)
unsigned_diff() {
  awk -v n="$1" -v p="$2" 'BEGIN{
    d = n - p;
    if (d < 0) d += 18446744073709551616;
    printf "%.0f", d
  }'
}

# list candidate interfaces (exclude loopback, docker, bridge, virtual common prefixes)
list_ifaces() {
  awk -F: 'NR>2 {
    gsub(/ /,"",$1);
    name=$1;
    if (name == "lo") next;
    if (name ~ /^(docker|br-|veth|vmnet|virbr|vboxnet|wlx|ifb|tunl|sit)/) next;
    print name
  }' /proc/net/dev
}

# all interfaces including tun/tap and veth (if you want to include them)
list_all_ifaces() {
  awk -F: 'NR>2 { gsub(/ /,"",$1); if ($1!="lo") print $1 }' /proc/net/dev
}

# read bytes for all interfaces -> prints "iface rx tx" lines
read_all_stats() {
  if [[ -d /sys/class/net ]]; then
    for iface_path in /sys/class/net/*; do
      iface=$(basename "$iface_path")
      [[ "$iface" == "lo" ]] && continue
      rx_file="$iface_path/statistics/rx_bytes"
      tx_file="$iface_path/statistics/tx_bytes"
      if [[ -r "$rx_file" && -r "$tx_file" ]]; then
        rx=$(cat "$rx_file" 2>/dev/null || echo "")
        tx=$(cat "$tx_file" 2>/dev/null || echo "")
        if [[ -n "$rx" && -n "$tx" ]]; then
          printf "%s %s %s\n" "$iface" "$rx" "$tx"
        fi
      fi
    done
    return 0
  fi
  awk -F'[: ]+' 'NR>2 { gsub(/ /,"",$1); iface=$1; rx=$2; tx=$10; printf("%s %s %s\n", iface, rx, tx)}' /proc/net/dev
}

# get default route interface (IPv4)
default_iface() {
  ip -4 route show default 2>/dev/null | awk 'NR==1 {print $5}'
}

# prefer VPN interface if active (tun0)
vpn_iface() {
  if [[ -d /sys/class/net/tun0 ]]; then
    local state
    state=$(cat /sys/class/net/tun0/operstate 2>/dev/null || echo "down")
    if [[ "$state" == "up" ]]; then
      echo "tun0"
      return 0
    fi
  fi
  return 1
}

# try to install minimal deps (iproute2, procps) - best effort
ensure_deps() {
  if command -v ip >/dev/null && [[ -r /proc/net/dev ]]; then
    echo "deps ok" >&2
    return 0
  fi
  echo "Attempting to install dependencies..." >&2
  if command -v apt-get >/dev/null; then
    sudo apt-get update && sudo apt-get install -y iproute2 procps || return 1
  elif command -v dnf >/dev/null; then
    sudo dnf install -y iproute procps-ng || return 1
  elif command -v pacman >/dev/null; then
    sudo pacman -Sy --noconfirm iproute2 procps-ng || return 1
  else
    echo "No supported package manager found; install iproute2/procps manually." >&2
    return 1
  fi
}

if $ENSURE_DEPS; then
  ensure_deps || true
fi

# --- Initialization ---
if [[ ! -r /proc/net/dev ]]; then
  echo "No net"
  exit 0
fi

# previous counters stored in associative arrays (bash)
declare -A prev_rx prev_tx smooth_rx_bps smooth_tx_bps

# Prime with current bytes
while read -r iface rx tx; do
  prev_rx["$iface"]="$rx"
  prev_tx["$iface"]="$tx"
  smooth_rx_bps["$iface"]="0"
  smooth_tx_bps["$iface"]="0"
done < <(read_all_stats)

# previous timestamp (in-memory only)
prev_ts="0"

# Main persistent loop
while true; do
  t_now=$(date +%s.%N)

  # read current stats
  declare -A cur_rx cur_tx delta_rx delta_tx
  while read -r iface rx tx; do
    cur_rx["$iface"]="$rx"
    cur_tx["$iface"]="$tx"
  done < <(read_all_stats)

  # compute deltas and choose best interface based on rx+tx delta
  best_iface=""
  best_total_delta=0
  total_rx_delta=0
  total_tx_delta=0

  for iface in "${!cur_rx[@]}"; do
    if [[ -z "${prev_rx[$iface]+set}" || -z "${prev_tx[$iface]+set}" ]]; then
      # New or reappeared iface; avoid huge spike and reset smoothing.
      d_rx=0
      d_tx=0
      smooth_rx_bps["$iface"]="0"
      smooth_tx_bps["$iface"]="0"
    else
      p_rx=${prev_rx["$iface"]}
      p_tx=${prev_tx["$iface"]}
      d_rx=$(unsigned_diff "${cur_rx[$iface]}" "$p_rx")
      d_tx=$(unsigned_diff "${cur_tx[$iface]}" "$p_tx")
    fi
    delta_rx["$iface"]="$d_rx"
    delta_tx["$iface"]="$d_tx"

    # accumulate totals (useful fallback)
    total_rx_delta=$(( total_rx_delta + d_rx ))
    total_tx_delta=$(( total_tx_delta + d_tx ))

    total_delta=$(( d_rx + d_tx ))
    if (( total_delta > best_total_delta )); then
      best_total_delta=$total_delta
      best_iface="$iface"
    fi
  done

  # If best_iface is empty (shouldn't happen), pick first non-loopback
  if [[ -z "$best_iface" ]]; then
    for i in $(list_all_ifaces); do best_iface="$i"; break; done
  fi

  # compute time delta (in-memory timestamp)
  if [[ "$prev_ts" == "0" ]]; then
    time_delta="$INTERVAL"
  else
    time_delta=$(awk -v a="$t_now" -v b="$prev_ts" -v i="$INTERVAL" 'BEGIN{t=a-b; if(t<=0) t=i; print t}')
  fi
  prev_ts="$t_now"

  # compute raw bps and apply smoothing per-interface
  for iface in "${!cur_rx[@]}"; do
    dr=${delta_rx["$iface"]}
    dt=${delta_tx["$iface"]}
    # use awk to compute float bps
    rx_bps_now=$(awk -v d="$dr" -v t="$time_delta" 'BEGIN{ if(t<=0) t=0.0001; printf "%.6f", d/t }')
    tx_bps_now=$(awk -v d="$dt" -v t="$time_delta" 'BEGIN{ if(t<=0) t=0.0001; printf "%.6f", d/t }')

    # get previous smooth values
    prev_srx=${smooth_rx_bps["$iface"]:="0"}
    prev_stx=${smooth_tx_bps["$iface"]:="0"}

    # EMA smoothing
    smooth_rx=$(awk -v a="$SMOOTH_ALPHA" -v p="$prev_srx" -v x="$rx_bps_now" 'BEGIN{printf "%.6f", a*x + (1-a)*p}')
    smooth_tx=$(awk -v a="$SMOOTH_ALPHA" -v p="$prev_stx" -v x="$tx_bps_now" 'BEGIN{printf "%.6f", a*x + (1-a)*p}')

    smooth_rx_bps["$iface"]="$smooth_rx"
    smooth_tx_bps["$iface"]="$smooth_tx"
  done

  # Choose display interface:
  # - prefer VPN (tun0) only if it is the default route or actually carrying traffic
  # - else default route interface if present
  # - else best_iface by traffic
  chosen_iface=""
  def_iface=$(default_iface)
  tun0_active=false
  if vpn_iface >/dev/null; then
    tun0_active=true
  fi

  if $tun0_active; then
    tun0_delta=$(( ${delta_rx[tun0]:-0} + ${delta_tx[tun0]:-0} ))
    if [[ "$def_iface" == "tun0" || "$tun0_delta" -gt 0 ]]; then
      chosen_iface="tun0"
    fi
  fi

  if [[ -z "$chosen_iface" ]]; then
    if [[ -n "$def_iface" && -n "${cur_rx[$def_iface]+set}" ]]; then
      chosen_iface="$def_iface"
    else
      chosen_iface="$best_iface"
    fi
  fi

  chosen_rx_bps=${smooth_rx_bps["$chosen_iface"]:="0"}
  chosen_tx_bps=${smooth_tx_bps["$chosen_iface"]:="0"}

  # If chosen iface shows near-zero but totals >0, prefer the busiest iface; fall back to totals if needed.
  total_bps=$(awk -v r="$total_rx_delta" -v t="$total_tx_delta" -v dt="$time_delta" 'BEGIN{ if(dt<=0) dt=0.0001; printf "%.6f", (r+t)/dt }')
  if ! awk -v x="$chosen_rx_bps" -v y="$chosen_tx_bps" -v tot="$total_bps" 'BEGIN{ if(tot<=0) exit 0; if((x+y)>=(tot*0.01)) exit 0; exit 1 }'; then
    if [[ -n "$best_iface" && "$best_iface" != "$chosen_iface" ]]; then
      chosen_iface="$best_iface"
      chosen_rx_bps=${smooth_rx_bps["$chosen_iface"]:="0"}
      chosen_tx_bps=${smooth_tx_bps["$chosen_iface"]:="0"}
    else
      sum_srx=0; sum_stx=0
      for iface in "${!smooth_rx_bps[@]}"; do
        sum_srx=$(awk -v a="$sum_srx" -v b="${smooth_rx_bps[$iface]}" 'BEGIN{printf "%.6f", a+b}')
        sum_stx=$(awk -v a="$sum_stx" -v b="${smooth_tx_bps[$iface]}" 'BEGIN{printf "%.6f", a+b}')
      done
      chosen_iface="total"
      chosen_rx_bps="$sum_srx"
      chosen_tx_bps="$sum_stx"
    fi
  fi

  # Format and output for i3blocks (single line)
  DOWN=$(human_rate "$chosen_rx_bps")
  UP=$(human_rate "$chosen_tx_bps")

  # find IP of chosen iface if not total
  if [[ "$chosen_iface" == "total" ]]; then
    IP="-"
    iface_display="all"
  else
    IP=$(ip -4 addr show dev "$chosen_iface" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1 || echo "-")
    iface_display="$chosen_iface"
  fi

  # Output line for i3blocks
  printf "↑ %s    ↓ %s    |    %s   (%s)\n" "$UP" "$DOWN" "$IP" "$iface_display"

  # Debug printing to stderr/terminal if requested
  if $DEBUG; then
    echo "DEBUG: chosen=$chosen_iface, rx_bps=$chosen_rx_bps tx_bps=$chosen_tx_bps total_delta_rx=$total_rx_delta total_delta_tx=$total_tx_delta time_delta=$time_delta" >&2
    # per-interface (small list)
    for iface in "${!cur_rx[@]}"; do
      echo "  $iface: d_rx=${delta_rx[$iface]} d_tx=${delta_tx[$iface]} srx=${smooth_rx_bps[$iface]} stx=${smooth_tx_bps[$iface]}" >&2
    done
  fi

  # store prev for next loop (drop missing interfaces)
  unset prev_rx prev_tx
  declare -A prev_rx prev_tx
  for iface in "${!cur_rx[@]}"; do
    prev_rx["$iface"]="${cur_rx[$iface]}"
    prev_tx["$iface"]="${cur_tx[$iface]}"
  done

  sleep "$INTERVAL"
done
