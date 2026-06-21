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
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_MEMORY=""

# =========================
# Logic
# =========================
total="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
available="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"

used=$((total - available))
pct=$((100 * used / total))

used_g="$(awk -v kb="$used" 'BEGIN {printf "%.1f", kb/1048576}')"

# =========================
# Color Logic
# =========================
color="$TEXT"

if [ "$pct" -ge 85 ]; then
  color="$RED"
elif [ "$pct" -ge 65 ]; then
  color="$WARN"
fi

# =========================
# Output
# =========================
printf "<span color='%s'>| %s </span><span color='%s'>%sG</span>\n" \
  "$MUTED" "$ICON_MEMORY" "$color" "$used_g"