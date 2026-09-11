#!/usr/bin/env bash
set -u
source "$(dirname "$0")/colors.sh"

# =========================
# Config
# =========================
MUTED="#ffffff"
TEXT="#ffffff"
ICON_COLOR="#a6e3a1"

# =========================
# Helpers
# =========================
signal_bar() {
  pkill -RTMIN+10 i3blocks 2>/dev/null || true
}

# =========================
# Actions
# =========================
case "${BLOCK_BUTTON:-}" in
  1)
    foot -e "$HOME/.config/i3blocks/scripts/menu/vol-brigh_menu.sh" >/dev/null 2>&1 &
    ;;
  3)
    wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle 2>/dev/null
    signal_bar
    ;;
  4)
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ 2>/dev/null
    signal_bar
    ;;
  5)
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- 2>/dev/null
    signal_bar
    ;;
esac

# =========================
# Icons (Nerd Font / Font Awesome)
# =========================
ICON_VOLUME_HIGH=""
ICON_VOLUME_MED=""
ICON_VOLUME_LOW=""
ICON_VOLUME_MUTED=""

# =========================
# Logic
# =========================
line="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)"

vol="$(printf "%s\n" "$line" | awk '{for (i=1;i<=NF;i++) if ($i ~ /^[0-9.]+$/) {printf "%d", $i*100; exit}}')"
[ -z "$vol" ] && vol=0

icon="$ICON_VOLUME_LOW"
color="$(percentage_color "$vol")"

if printf "%s" "$line" | grep -qi MUTED; then
  icon="$ICON_VOLUME_MUTED"
  color="$SECONDARY_TEXT"

elif [ "$vol" -ge 70 ]; then
  icon="$ICON_VOLUME_HIGH"

elif [ "$vol" -ge 30 ]; then
  icon="$ICON_VOLUME_MED"

else
  icon="$ICON_VOLUME_LOW"
fi

# =========================
# Output
# =========================
printf "<span color='%s'>| %s </span><span color='%s'>%s%%</span>\n" "$color" "$icon" "$color" "$vol"
