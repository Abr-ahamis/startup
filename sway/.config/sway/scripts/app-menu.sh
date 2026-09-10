#!/usr/bin/env bash
set -u

launcher="$HOME/.config/sway/scripts/launch-app.sh"
wofi_menu() {
  local prompt="$1"
  shift
  printf '%s\n' "$@" | wofi --dmenu --prompt "$prompt" --insensitive
}

choose_category() {
  wofi_menu \
    '󰍉  Sections' \
    '󰀻  Common apps' \
    '󰖟  Internet' \
    '󰆍  Development' \
    '󰝤  Media and graphics' \
    '󰒓  System tools'
}

choose_app() {
  local subsection="$1"
  case "$subsection" in
    '  Everyday')
      wofi_menu '  Everyday apps' '  Terminal' '  File manager' '󰏫  Text editor' '󰄀  Screenshot' '󰅬  Back'
      ;;
    '  Web and chat')
      wofi_menu '  Web and chat' '󰈹  Browser' '  Secondary browser' '  Telegram' '󰅬  Back'
      ;;
    '󰈮  Code and notes')
      wofi_menu '󰈮  Code and notes' '󰨞  VS Code' '󰠮  Obsidian' '  Terminal' '󰅬  Back'
      ;;
    '󰻝  Capture')
      wofi_menu '󰝤  Media and graphics' '󰄀  Screenshot' '  File manager' '󰅬  Back'
      ;;
    '󰒓  Desktop controls')
      wofi_menu '󰒓  System tools' '⏻  Power menu' '󰖩  Wi-Fi menu' '󰂯  Bluetooth menu' '󰕾  Volume and brightness' '󰅬  Back'
      ;;
  esac
}

choose_subsection() {
  local category="$1"
  case "$category" in
    '󰀻  Common apps') wofi_menu '󰀻  Common apps' '  Everyday' '󰅬  Back' ;;
    '󰖟  Internet') wofi_menu '󰖟  Internet' '  Web and chat' '󰅬  Back' ;;
    '󰆍  Development') wofi_menu '󰆍  Development' '󰈮  Code and notes' '󰅬  Back' ;;
    '󰝤  Media and graphics') wofi_menu '󰝤  Media and graphics' '󰻝  Capture' '󰅬  Back' ;;
    '󰒓  System tools') wofi_menu '󰒓  System tools' '󰒓  Desktop controls' '󰅬  Back' ;;
  esac
}

launch_choice() {
  case "$1" in
    '  Terminal') exec "$launcher" terminal ;;
    '  File manager') exec "$launcher" filemanager ;;
    '󰏫  Text editor') exec "$launcher" editor ;;
    '󰄀  Screenshot') exec "$launcher" screenshot ;;
    '󰈹  Browser') exec "$launcher" browser ;;
    '  Secondary browser') exec "$launcher" browser-secondary ;;
    '  Telegram') exec "$launcher" telegram ;;
    '󰨞  VS Code') exec "$launcher" code ;;
    '󰠮  Obsidian') exec "$launcher" obsidian ;;
    '⏻  Power menu') exec foot bash -lc '"$HOME/.config/i3blocks/scripts/menu/power_menu.sh"; exec bash' ;;
    '󰖩  Wi-Fi menu') exec foot bash -lc '"$HOME/.config/i3blocks/scripts/menu/wifi_menu.sh"; exec bash' ;;
    '󰂯  Bluetooth menu') exec foot bash -lc '"$HOME/.config/i3blocks/scripts/menu/bt_menu.sh"; exec bash' ;;
    '󰕾  Volume and brightness') exec foot bash -lc '"$HOME/.config/i3blocks/scripts/menu/vol-brigh_menu.sh"; exec bash' ;;
  esac
}

while :; do
  category="$(choose_category || true)"
  [[ -n "$category" ]] || exit 0
  subsection="$(choose_subsection "$category" || true)"
  [[ -n "$subsection" ]] || exit 0
  [[ "$subsection" == *Back ]] && continue
  choice="$(choose_app "$subsection" || true)"
  [[ -n "$choice" ]] || exit 0
  [[ "$choice" == *Back ]] && continue
  launch_choice "$choice"
  exit 0
done