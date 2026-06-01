#!/usr/bin/env bash
set -u

MUTED="#6e7681"
TEXT="#c9d1d9"

signal_bar() {
  pkill -RTMIN+10 i3blocks 2>/dev/null || true
}

case "${BLOCK_BUTTON:-}" in
  1) nohup "$HOME/.config/sway/scripts/volume_menu.sh" >/dev/null 2>&1 & ;;
  3) wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle 2>/dev/null; signal_bar ;;
  4) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ 2>/dev/null; signal_bar ;;
  5) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- 2>/dev/null; signal_bar ;;
esac

line="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)"
vol="$(printf "%s\n" "$line" | awk '{for (i=1;i<=NF;i++) if ($i ~ /^[0-9.]+$/) {printf "%d", $i*100; exit}}')"
[ -z "$vol" ] && vol=0

if printf "%s" "$line" | grep -qi MUTED; then
  icon=$'\uf6a9'; icon_color="$MUTED"
elif [ "$vol" -ge 70 ]; then
  icon=$'\uf028'; icon_color="$TEXT"
elif [ "$vol" -ge 30 ]; then
  icon=$'\uf027'; icon_color="$TEXT"
else
  icon=$'\uf027'; icon_color="$TEXT"
fi

printf "<span color='%s'>%s</span>\n" "$icon_color" "$icon"
