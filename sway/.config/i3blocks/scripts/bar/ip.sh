#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
MUTED="#6e7681"
TEXT="#c9d1d9"

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    foot -e sudo "$HOME/.config/i3blocks/scripts/menu/wifi_menu.sh" >/dev/null 2>&1 &
    ;;
esac

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_GLOBE=""
ICON_NO_IP=""

# =========================
# Logic
# =========================
ipaddr="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"

# =========================
# Output
# =========================
if [ -z "$ipaddr" ]; then
  printf "<span color='%s'>%s </span><span color='%s'>no ip</span>\n" \
    "$MUTED" "$ICON_NO_IP" "$MUTED"
else
  printf "| <span color='%s'>%s </span><span color='%s'>%s</span>\n" \
    "$MUTED" "$ICON_GLOBE" "$TEXT" "$ipaddr"
fi