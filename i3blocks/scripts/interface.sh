#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
MUTED="#6e7681"
TEXT="#c9d1d9"

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_WIFI=""
ICON_ETH=""
ICON_UNKNOWN=""

# =========================
# Logic
# =========================
iface="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"

icon="$ICON_UNKNOWN"

case "$iface" in
  wl*) icon="$ICON_WIFI" ;;
  eth*|en*) icon="$ICON_ETH" ;;
  *) 
    icon="$ICON_ETH"
    [ -z "$iface" ] && iface="---"
    ;;
esac

# =========================
# Output
# =========================
printf "| <span color='%s'>%s </span><span color='%s'>%s</span>\n" \
  "$MUTED" "$icon" "$TEXT" "$iface"