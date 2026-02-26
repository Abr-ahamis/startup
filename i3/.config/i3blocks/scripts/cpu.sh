#!/bin/bash

read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
prev_idle=$((idle + iowait))
prev_total=$((user + nice + system + idle + iowait + irq + softirq + steal))

sleep 0.1

read cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
idle_now=$((idle + iowait))
total_now=$((user + nice + system + idle + iowait + irq + softirq + steal))

diff_total=$((total_now - prev_total))
diff_idle=$((idle_now - prev_idle))

cpu_usage=$(awk -v idle="$diff_idle" -v total="$diff_total" \
  'BEGIN { printf "%3.0f", 100 * (1 - idle/total) }')

echo " CPU ${cpu_usage}%"
                           
