#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
MUTED="#6e7681"
TEXT="#c9d1d9"
WARN="#d4902a"
RED="#f85149"

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1) ;;
esac

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_CPU=""

# =========================
# State
# =========================
state_dir="${XDG_RUNTIME_DIR:-/tmp}"
state="${state_dir}/i3blocks_cpu_${UID:-$(id -u)}"

# =========================
# CPU Calculation Logic
# =========================
read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat

idle_all=$((idle + iowait))
non_idle=$((user + nice + system + irq + softirq + steal))
total=$((idle_all + non_idle))

prev_total="$total"
prev_idle="$idle_all"

if [ -r "$state" ]; then
  read -r prev_total prev_idle < "$state"
fi

printf "%s %s\n" "$total" "$idle_all" > "$state" 2>/dev/null || true

total_delta=$((total - prev_total))
idle_delta=$((idle_all - prev_idle))

if [ "$total_delta" -le 0 ]; then
  pct=0
else
  pct=$(((100 * (total_delta - idle_delta)) / total_delta))
fi

# =========================
# Color Logic
# =========================
color="$TEXT"

if [ "$pct" -ge 80 ]; then
  color="$RED"
elif [ "$pct" -ge 50 ]; then
  color="$WARN"
fi

# =========================
# Output
# =========================
printf "<span color='%s'>| %s </span><span color='%s'>%s%%</span>\n" \
  "$MUTED" "$ICON_CPU" "$color" "$pct"