#!/usr/bin/env bash
# CPU block that reads cpu_percent from GNOME exported JSON or falls back to /proc/stat
JSON=/tmp/gnome_status.json
SAMPLE=0.6

while true; do
  if [[ -r "$JSON" ]]; then
    cpu=$(jq -r '.cpu_percent // -1' "$JSON" 2>/dev/null)
    if [[ "$cpu" -ge 0 ]]; then
      echo " CPU ${cpu}%"
      echo ""
      sleep "$SAMPLE"
      continue
    fi
  fi

  # Fallback: compute from /proc/stat (fast single sample)
  # A tiny in-script sampler (not ideal for absolute precision but okay)
  read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  prev_total=$((user+nice+system+idle+iowait+irq+softirq+steal))
  prev_idle=$((idle + iowait))
  sleep 0.4
  read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  total=$((user+nice+system+idle+iowait+irq+softirq+steal))
  idle_now=$((idle + iowait))

  diff_total=$((total - prev_total))
  diff_idle=$((idle_now - prev_idle))

  if [[ $diff_total -gt 0 ]]; then
    cpu_usage=$(( (100 * (diff_total - diff_idle)) / diff_total ))
  else
    cpu_usage=0
  fi

  echo " CPU ${cpu_usage}%"
  echo ""
  sleep "$SAMPLE"
done
