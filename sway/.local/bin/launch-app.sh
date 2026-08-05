#!/usr/bin/env bash
# Launch a preferred application with portable fallbacks.
set -u
user_home="${HOME:-/tmp}"

notify_missing() { command -v notify-send >/dev/null 2>&1 && notify-send 'Startup setup' "No application available for: $1"; printf 'No application available for: %s\n' "$1" >&2; }
launch_first() {
  local command
  for command in "$@"; do
    if command -v "$command" >/dev/null 2>&1; then exec "$command"; fi
  done
  notify_missing "$1"; exit 127
}

case "${1:-}" in
  terminal) launch_first foot alacritty kitty gnome-terminal xterm ;;
  terminal-secondary) launch_first gnome-terminal foot alacritty kitty xterm ;;
  filemanager) launch_first nautilus nemo thunar pcmanfm ;;
  browser) launch_first firefox chromium google-chrome ;;
  browser-secondary) launch_first brave-browser chromium firefox ;;
  editor) launch_first gnome-text-editor gedit mousepad ;;
  screenshot) if command -v flameshot >/dev/null 2>&1; then exec flameshot gui; elif command -v grim >/dev/null 2>&1; then mkdir -p "$user_home/Pictures" && exec grim "$user_home/Pictures/screenshot-$(date +%F-%H%M%S).png"; fi; notify_missing screenshot; exit 127 ;;
  telegram) launch_first telegram-desktop Telegram ;;
  code) launch_first code codium ;;
  obsidian) launch_first obsidian ;;
  *) echo "Usage: $0 {terminal|terminal-secondary|filemanager|browser|browser-secondary|editor|screenshot|telegram|code|obsidian}" >&2; exit 2 ;;
esac
