#!/bin/bash
# Combined i3blocks status script: CPU, Memory, Swap, Network, Battery, Date
set -u

# ---- Config ----
INTERVAL=1.0        # seconds
SMOOTH_ALPHA=0.25   # network EMA smoothing factor (0..1)

# ---- Icons ----
ICON_CPU=""
ICON_MEM=""
ICON_SWAP=""
ICON_UP=""
ICON_DOWN=""
ICON_GLOBE=""
ICON_WIFI=""
ICON_BAT_LOW=""
ICON_BAT_MID=""
ICON_BAT_HIGH=""
ICON_CAL=""
ICON_CLOCK=""

# ---- Helpers ----
human_rate() {
  awk -v bps="$1" 'BEGIN{
    if (bps == "" || bps < 0) bps = 0;
    if (bps < 1000) { printf("%.0f B/s", bps); }
    else if (bps < 1000*1000) { printf("%.1f K/s", bps/1000); }
    else if (bps < 1000*1000*1000) { printf("%.2f M/s", bps/(1000*1000)); }
    else { printf("%.2f G/s", bps/(1000*1000*1000)); }
  }'
}

unsigned_diff() {
  awk -v n="$1" -v p="$2" 'BEGIN{
    d = n - p;
    if (d < 0) d += 18446744073709551616;
    printf "%.0f", d
  }'
}

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

default_iface() {
  ip -4 route show default 2>/dev/null | awk 'NR==1 {print $5}'
}

vpn_iface_active() {
  if [[ -d /sys/class/net/tun0 ]]; then
    state=$(cat /sys/class/net/tun0/operstate 2>/dev/null || echo "down")
    [[ "$state" == "up" ]]
  else
    return 1
  fi
}

# ---- Initialize network state ----
declare -A prev_rx prev_tx smooth_rx_bps smooth_tx_bps
while read -r iface rx tx; do
  prev_rx["$iface"]="$rx"
  prev_tx["$iface"]="$tx"
  smooth_rx_bps["$iface"]="0"
  smooth_tx_bps["$iface"]="0"
done < <(read_all_stats)
prev_ts="0"

# ---- Main loop ----
while true; do
  # CPU / Mem / Swap from top
  top_out=$(top -bn1)
  cpu_usage=$(awk -F'[:, ]+' '/^%Cpu\(s\):/ { for (i=1;i<=NF;i++) if ($i=="id") { id=$(i-1); } }
    END { if (id=="") { print "0"; } else { printf "%3.0f", 100 - id; } }' <<<"$top_out")

  mem_line=$(awk -F'[:, ]+' '/^MiB Mem/ {print $0}' <<<"$top_out")
  swap_line=$(awk -F'[:, ]+' '/^MiB Swap/ {print $0}' <<<"$top_out")

  mem_used=$(awk -F'[, ]+' '{ for (i=1;i<=NF;i++) if ($i=="used") { print $(i-1); exit } }' <<<"$mem_line")
  mem_total=$(awk -F'[, ]+' '{ for (i=1;i<=NF;i++) if ($i=="total") { print $(i-1); exit } }' <<<"$mem_line")
  swap_used=$(awk -F'[, ]+' '{ for (i=1;i<=NF;i++) if ($i=="used") { print $(i-1); exit } }' <<<"$swap_line")
  swap_total=$(awk -F'[, ]+' '{ for (i=1;i<=NF;i++) if ($i=="total") { print $(i-1); exit } }' <<<"$swap_line")

  mem_used=${mem_used:-0}
  mem_total=${mem_total:-0}
  swap_used=${swap_used:-0}
  swap_total=${swap_total:-0}

  # Battery
  if [[ -d /sys/class/power_supply/BAT0 ]]; then
    capacity=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "0")
    if [ "$capacity" -le 50 ]; then
      bat_icon="$ICON_BAT_LOW"
    elif [ "$capacity" -le 90 ]; then
      bat_icon="$ICON_BAT_MID"
    else
      bat_icon="$ICON_BAT_HIGH"
    fi
    BATTERY="$bat_icon $capacity%"
  else
    BATTERY=" N/A"
  fi

  # Date/Time
  DATE_STR=$(date +"$ICON_CAL  %Y-%m-%d |  $ICON_CLOCK  %H:%M")

  # Network
  t_now=$(date +%s.%N)
  declare -A cur_rx cur_tx delta_rx delta_tx
  while read -r iface rx tx; do
    cur_rx["$iface"]="$rx"
    cur_tx["$iface"]="$tx"
  done < <(read_all_stats)

  best_iface=""
  best_total_delta=0
  total_rx_delta=0
  total_tx_delta=0

  for iface in "${!cur_rx[@]}"; do
    if [[ -z "${prev_rx[$iface]+set}" || -z "${prev_tx[$iface]+set}" ]]; then
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

    total_rx_delta=$(( total_rx_delta + d_rx ))
    total_tx_delta=$(( total_tx_delta + d_tx ))
    total_delta=$(( d_rx + d_tx ))
    if (( total_delta > best_total_delta )); then
      best_total_delta=$total_delta
      best_iface="$iface"
    fi
  done

  if [[ -z "$best_iface" ]]; then
    for i in "${!cur_rx[@]}"; do best_iface="$i"; break; done
  fi

  if [[ "$prev_ts" == "0" ]]; then
    time_delta="$INTERVAL"
  else
    time_delta=$(awk -v a="$t_now" -v b="$prev_ts" -v i="$INTERVAL" 'BEGIN{t=a-b; if(t<=0) t=i; print t}')
  fi
  prev_ts="$t_now"

  for iface in "${!cur_rx[@]}"; do
    dr=${delta_rx["$iface"]}
    dt=${delta_tx["$iface"]}
    rx_bps_now=$(awk -v d="$dr" -v t="$time_delta" 'BEGIN{ if(t<=0) t=0.0001; printf "%.6f", d/t }')
    tx_bps_now=$(awk -v d="$dt" -v t="$time_delta" 'BEGIN{ if(t<=0) t=0.0001; printf "%.6f", d/t }')

    prev_srx=${smooth_rx_bps["$iface"]:="0"}
    prev_stx=${smooth_tx_bps["$iface"]:="0"}

    smooth_rx=$(awk -v a="$SMOOTH_ALPHA" -v p="$prev_srx" -v x="$rx_bps_now" 'BEGIN{printf "%.6f", a*x + (1-a)*p}')
    smooth_tx=$(awk -v a="$SMOOTH_ALPHA" -v p="$prev_stx" -v x="$tx_bps_now" 'BEGIN{printf "%.6f", a*x + (1-a)*p}')

    smooth_rx_bps["$iface"]="$smooth_rx"
    smooth_tx_bps["$iface"]="$smooth_tx"
  done

  chosen_iface=""
  def_iface=$(default_iface)
  if vpn_iface_active; then
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

  DOWN=$(human_rate "$chosen_rx_bps")
  UP=$(human_rate "$chosen_tx_bps")
  if [[ "$chosen_iface" == "total" ]]; then
    IP="-"
    iface_display="all"
  else
    IP=$(ip -4 addr show dev "$chosen_iface" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1 || echo "-")
    iface_display="$chosen_iface"
  fi

  # Output (simple editable line)
  echo "$ICON_UP  $UP   |   $ICON_DOWN  $DOWN   |   $ICON_CPU CPU ${cpu_usage}%   |   $ICON_MEM  $mem_used / $mem_total MiB   |   $ICON_SWAP  $swap_used / $swap_total MiB   |  $ICON_GLOBE $IP  |   $ICON_WIFI $iface_display  |   $DATE_STR   |   $BATTERY"

  unset prev_rx prev_tx
  declare -A prev_rx prev_tx
  for iface in "${!cur_rx[@]}"; do
    prev_rx["$iface"]="${cur_rx[$iface]}"
    prev_tx["$iface"]="${cur_tx[$iface]}"
  done

  sleep "$INTERVAL"
done

# ---- Editable output template ----
# echo " $ICON_UP  $UP  |  $ICON_DOWN  $DOWN  |  $ICON_CPU CPU ${cpu_usage}%  |  $ICON_MEM  $mem_used / $mem_total MiB  |  $ICON_SWAP $swap_used / $swap_total MiB  |  $ICON_GLOBE $IP  |   $ICON_WIFI  $iface_display  |  $DATE_STR  |  $BATTERY"
