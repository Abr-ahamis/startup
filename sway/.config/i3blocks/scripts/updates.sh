#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
MUTED="#6e7681"
WARN="#d4902a"

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_UPDATES=""

# =========================
# Logic
# =========================
count=0

if command -v checkupdates >/dev/null 2>&1; then
  count="$(checkupdates 2>/dev/null | wc -l)"
elif command -v apt >/dev/null 2>&1; then
  count="$(apt list --upgradeable 2>/dev/null | awk 'NR>1 {c++} END {print c+0}')"
fi

# =========================
# Color Logic
# =========================
color="$MUTED"
[ "$count" -gt 0 ] && color="$WARN"

# =========================
# Output
# =========================
printf "<span color='%s'>| %s </span><span color='%s'>%s</span>\n" \
  "$MUTED" "$ICON_UPDATES" "$color" "$count"