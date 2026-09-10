# Managed by startup: environment. Idempotent - safe to source repeatedly
# from both Bash and Zsh (POSIX sh syntax only).

# PATH hygiene: make sure private bins are present, without duplicates.
_startup_pp() {
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$1:$PATH" ;;
  esac
}
if [ -n "${HOME:-}" ]; then
  _startup_pp "$HOME/.local/bin"
fi
[ -n "${XDG_BIN_HOME:-}" ] && _startup_pp "$XDG_BIN_HOME"
unset -f _startup_pp 2>/dev/null || true
export PATH

# Editors.
export EDITOR="${EDITOR:-vim}"
export VISUAL="${VISUAL:-$EDITOR}"

# Readline configuration.
export INPUTRC="${INPUTRC:-${XDG_CONFIG_HOME:-$HOME/.config}/startup/inputrc}"

# Directory colors (only when GNU coreutils dircolors is available).
if command -v dircolors >/dev/null 2>&1; then
  _startup_dc="${XDG_CONFIG_HOME:-$HOME/.config}/startup/dir_colors"
  if [ -r "$_startup_dc" ]; then
    eval "$(dircolors -b "$_startup_dc" 2>/dev/null)"
  fi
  unset _startup_dc
fi
