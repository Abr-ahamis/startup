#!/usr/bin/env bash
set -u

# =========================
# Config
# =========================
TEXT="#c9d1d9"

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    foot bash -c "brightnessctl -m; echo; read -rp 'Set brightness (e.g. 50%): ' val; if [[ -n \"$val\" ]]; then brightnessctl set \"$val\"; fi; exec bash" >/dev/null 2>&1 &
    ;;
esac

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_BRIGHTNESS=""

# =========================
# Helpers
# =========================
signal_bar() {
  pkill -RTMIN+11 i3blocks 2>/dev/null || true
}

# =========================
# Logic
# =========================
current="$(brightnessctl get 2>/dev/null || printf 0)"
max="$(brightnessctl max 2>/dev/null || printf 1)"

[ "$max" -le 0 ] && max=1

pct=$((100 * current / max))

# =========================
# Output
# =========================
printf "<span color='%s'>| %s %s%%</span>\n" \
  "$TEXT" "$ICON_BRIGHTNESS" "$pct"