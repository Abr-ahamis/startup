# Managed by startup: shared shell features for Bash and Zsh.
# Loaded once at the end of ~/.bashrc / ~/.zshrc (see the startup loader
# block). The whole file is POSIX sh; the only shell-specific parts run
# conditionally below.

[ "${_startup_loaded:-}" = 1 ] && return 0
_startup_loaded=1

_startup_dir="${XDG_CONFIG_HOME:-$HOME/.config}/startup"

# --- environment / aliases (always) ---------------------------------------
[ -r "$_startup_dir/env.sh" ] && . "$_startup_dir/env.sh"
[ -r "$_startup_dir/aliases" ] && . "$_startup_dir/aliases"

# --- terminal detection -----------------------------------------------------
# Only interactive shells that are attached to a real terminal emulator get
# the managed prompt. Everything else (SSH, tmux without a terminal, editor
# shells, cron, ...) is left untouched.
_startup_terminal_allowed() {
  # 1. An explicit terminal-emulator identity (foot, GNOME Terminal/VTE, ...).
  case "${TERM_PROGRAM:-}" in
    foot|vte|gnome-terminal*|Tilix|alacritty|kitty|wezterm|konsole|xfce4-terminal|contour|rio|ghostty|xterm*|rxvt*|st*)
      return 0 ;;
  esac
  [ -n "${VTE_VERSION:-}" ] && return 0

  # 2. distrobox container envelope: we are inside a container that was
  #    entered from a local Wayland/X session (no SSH anywhere in the chain).
  if { [ -n "${DISTROBOX_ENTER_PATH:-}" ] || [ -n "${CONTAINER_ID:-}" ]; } && [ -f /run/.containerenv ]; then
    if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; then
      [ -z "${SSH_CONNECTION:-}" ] && [ -z "${SSH_CLIENT:-}" ] && return 0
    fi
  fi

  # 3. Fallback: walk the parent chain and look for a known emulator, skipping
  #    shells and container plumbing. PID namespaces are shared with the host,
  #    so the walk crosses the container boundary (conmon/podman/distrobox).
  _startup_p=${PPID:-0}
  _startup_i=0
  while [ "$_startup_i" -lt 24 ] && [ -n "$_startup_p" ] && [ "$_startup_p" -gt 1 ]; do
    _startup_c=$(ps -o comm= -p "$_startup_p" 2>/dev/null) || break
    _startup_c=${_startup_c##*/}
    case "$_startup_c" in
      foot|gnome-terminal*|gnome-terminal-server|xterm*|alacritty|kitty|wezterm|konsole|xfce4-terminal|contour|rio|ghostty|st|urxvt|mlterm)
        return 0 ;;
    esac
    case "$_startup_c" in
      sh|bash|dash|zsh|fish|conmon|catatonit|runc|podman|distrobox|distrobox-enter|sshd|sshd-session|systemd*|login|su|sudo|runuser|tmux|screen|mosh-server|nix-shell)
        _startup_p=$(ps -o ppid= -p "$_startup_p" 2>/dev/null | tr -d ' ') ;;
      *)
        break ;;
    esac
    _startup_i=$((_startup_i + 1))
  done
  return 1
}

case $- in
  *i*) _startup_interactive=1 ;;
  *)   _startup_interactive=0 ;;
esac

if [ "$_startup_interactive" -eq 1 ] && _startup_terminal_allowed; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    [ -r "$_startup_dir/prompt.zsh" ] && . "$_startup_dir/prompt.zsh"
  elif [ -n "${BASH_VERSION:-}" ]; then
    [ -r "$_startup_dir/prompt.sh" ] && . "$_startup_dir/prompt.sh"
  fi
fi

unset _startup_interactive _startup_p _startup_i _startup_c 2>/dev/null || true
