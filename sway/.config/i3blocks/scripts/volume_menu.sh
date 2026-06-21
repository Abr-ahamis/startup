#!/usr/bin/env bash
set -u

theme="$HOME/.config/rofi/themes/dark.rasi"
choice="$(printf "Mute Toggle\nVolume 30%%\nVolume 50%%\nVolume 70%%\nVolume 100%%\nOpen Mixer\n" | rofi -dmenu -i -p audio -theme "$theme")"
case "$choice" in
  "Mute Toggle") wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
  "Volume 30%") wpctl set-volume @DEFAULT_AUDIO_SINK@ 30% ;;
  "Volume 50%") wpctl set-volume @DEFAULT_AUDIO_SINK@ 50% ;;
  "Volume 70%") wpctl set-volume @DEFAULT_AUDIO_SINK@ 70% ;;
  "Volume 100%") wpctl set-volume @DEFAULT_AUDIO_SINK@ 100% ;;
  "Open Mixer") nohup pavucontrol >/dev/null 2>&1 & ;;
esac
pkill -RTMIN+10 i3blocks 2>/dev/null || true
