# Managed by startup: Bash prompt.
# Prefers a running starship (host Omarchy owns the prompt and must not be
# clobbered); falls back to a native two-line prompt with git status when
# starship is unavailable (e.g. inside distrobox containers).

_startup_dir="${XDG_CONFIG_HOME:-$HOME/.config}/startup"

_startup_prompt_starship() {
  command -v starship >/dev/null 2>&1 || return 1
  # The host session already runs starship; never clobber it.
  [ -n "${STARSHIP_SESSION_KEY:-}" ] && return 2
  _startup_cfg="$_startup_dir/starship.toml"
  [ -r "$_startup_cfg" ] && export STARSHIP_CONFIG="$_startup_cfg"
  if eval "$(starship init bash --print-full-init 2>/dev/null)"; then
    return 0
  fi
  return 1
}

_startup_dir_trunc() {
  # starship-style directory: ~ shortcut + last two path components.
  _startup_d=$1
  case "$_startup_d" in
    "$HOME") printf '%s' '~'; return 0 ;;
    "$HOME"/*) _startup_d="~${_startup_d#"$HOME"}" ;;
  esac
  _startup_tail=$(printf '%s' "$_startup_d" | tr '/' '\n' | sed '/^$/d' | tail -n 2 | paste -sd / -)
  if [ -n "$_startup_tail" ] && [ "$_startup_tail" != "$_startup_d" ]; then
    printf '…/%s' "$_startup_tail"
  else
    printf '%s' "$_startup_d"
  fi
}

_startup_git_status() {
  command -v git >/dev/null 2>&1 || return 0
  _startup_b=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || return 0
  [ -n "$_startup_b" ] || return 0
  _startup_dirty=$(git status --porcelain 2>/dev/null)
  if [ -n "$_startup_dirty" ]; then
    printf ' %s*' "$_startup_b"
  else
    printf ' %s' "$_startup_b"
  fi
}

_startup_update_prompt() {
  _startup_rc=$?
  _startup_pwd=$(_startup_dir_trunc "$PWD")
  _startup_git=$(_startup_git_status)
  if [ "$_startup_rc" -eq 0 ]; then
    _startup_arrow='❯'
  else
    _startup_arrow='✗'
  fi
}

_startup_prompt_native() {
  # A STARSHIP_SESSION_KEY may leak through distrobox even when the binary is
  # absent; clear it so later container shells cannot misbehave.
  unset STARSHIP_CONFIG STARSHIP_SESSION_KEY STARSHIP_SHELL STARSHIP_CACHE 2>/dev/null || true
  _startup_update_prompt
  PROMPT_COMMAND='_startup_update_prompt'
  PS1='\n\[\e[1;36m\][${_startup_pwd}${_startup_git}]\[\e[0m\] \[\e[1;36m\]${_startup_arrow}\[\e[0m\] '
}

_startup_prompt_starship
case $? in
  0|2) ;;
  *) _startup_prompt_native ;;
esac
