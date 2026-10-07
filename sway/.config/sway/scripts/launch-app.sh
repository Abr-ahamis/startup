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

launch_neovim() {
  local nvim_bin terminal
  if [[ -x "$user_home/.local/bin/nvim" ]]; then
    nvim_bin="$user_home/.local/bin/nvim"
  else
    nvim_bin="$(command -v nvim 2>/dev/null || true)"
  fi
  [[ -n "$nvim_bin" ]] || { notify_missing neovim; exit 127; }
  for terminal in foot alacritty kitty gnome-terminal xterm; do
    command -v "$terminal" >/dev/null 2>&1 || continue
    case "$terminal" in
      foot|alacritty|xterm) exec "$terminal" -e "$nvim_bin" ;;
      kitty) exec "$terminal" "$nvim_bin" ;;
      gnome-terminal) exec "$terminal" -- "$nvim_bin" ;;
    esac
  done
  notify_missing 'a terminal for neovim'
  exit 127
}

case "${1:-}" in
  terminal) launch_first foot alacritty kitty gnome-terminal xterm ;;
  terminal-secondary) launch_first gnome-terminal foot alacritty kitty xterm ;;
  neovim) launch_neovim ;;
  filemanager) launch_first nautilus nemo thunar pcmanfm ;;
  browser) launch_first brave-browser firefox google-chrome chromium ;;
  editor) launch_first gnome-text-editor gedit mousepad ;;
  screenshot) if command -v flameshot >/dev/null 2>&1; then exec flameshot gui; elif command -v grim >/dev/null 2>&1; then mkdir -p "$user_home/Pictures" && exec grim "$user_home/Pictures/screenshot-$(date +%F-%H%M%S).png"; fi; notify_missing screenshot; exit 127 ;;
  telegram) launch_first /opt/Telegram/./Telegram telegram-desktop Telegram ;;
  code) launch_first code codium ;;
  obsidian) launch_first obsidian ;;
  *) echo "Usage: $0 {terminal|terminal-secondary|neovim|filemanager|browser|editor|screenshot|telegram|code|obsidian}" >&2; exit 2 ;;
esac
