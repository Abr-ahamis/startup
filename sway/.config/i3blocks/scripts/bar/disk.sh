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
ICON_DISK=""

# =========================
# Logic
# =========================
pct="$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')"

color="$TEXT"

if [ "$pct" -ge 90 ]; then
  color="$RED"
elif [ "$pct" -ge 75 ]; then
  color="$WARN"
fi

# =========================
# Output
# =========================
printf "<span color='%s'>| %s </span><span color='%s'>%s%%</span>\n" \
  "$MUTED" "$ICON_DISK" "$color" "$pct"