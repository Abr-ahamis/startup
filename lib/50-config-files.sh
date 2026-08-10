#!/usr/bin/env bash
# Installs managed resources without deleting unrelated user files.

if [[ -n "${__SETUP_CONFIG_FILES_LOADED:-}" ]]; then return 0; fi
__SETUP_CONFIG_FILES_LOADED=1

validate_managed_tree() {
  local path="${1:-}" label="${2:-configuration}" file manifest
  case "$label" in
    Sway*)
      [[ -s "$path/config" ]] || { warn "$label is missing its config file: $path/config"; return 1; }
      # `sway -C` launches a Wayland backend and is not reliable from sudo,
      # a chroot, or a non-Sway desktop.  Validate the managed contract here;
      # the service stage reloads a real Sway session when one exists.
      grep -q '^bar[[:space:]]*{' "$path/config" || { warn "$label has no bar block: $path/config"; return 1; }
      grep -q 'status_command[[:space:]].*i3blocks' "$path/config" || { warn "$label has no i3blocks status command: $path/config"; return 1; }
      _setup_log_write INFO "$label native validation deferred to the Sway session"
      ;;
    User\ systemd*)
      manifest="$SETUP_RUNTIME_DIR/systemd-units.$$"
      find "$path" -type f \( -name '*.service' -o -name '*.timer' \) -print0 >"$manifest" 2>/dev/null || return 1
      while IFS= read -r -d '' file; do
        grep -q '^\[Unit\]' "$file" && grep -q '^\[Service\]' "$file" && grep -q '^ExecStart=' "$file" || { rm -f -- "$manifest"; warn "$label has an invalid unit structure: $file"; return 1; }
        [[ "$file" != *.timer ]] || grep -q '^\[Timer\]' "$file" || { rm -f -- "$manifest"; warn "$label has an invalid timer structure: $file"; return 1; }
      done <"$manifest"
      rm -f -- "$manifest"
      ;;
    GTK*)
      [[ -d "$path" ]] || return 1
      ;;
  esac
}

configure_backlight_access() {
  local rule_file="/etc/udev/rules.d/90-startup-backlight.rules"
  local sudoers_file="/etc/sudoers.d/startup-brightness"
  local temp_file sudoers_temp brightnessctl_path visudo_path group="video"

  # `sudo ./main.sh` can retain a user PATH without /usr/sbin.  Resolve the
  # standard system locations explicitly before relying on PATH.
  brightnessctl_path="$(command -v brightnessctl 2>/dev/null || true)"
  [[ -x /usr/bin/brightnessctl ]] && brightnessctl_path=/usr/bin/brightnessctl
  visudo_path="$(command -v visudo 2>/dev/null || true)"
  [[ -x /usr/sbin/visudo ]] && visudo_path=/usr/sbin/visudo
  if [[ -z "$brightnessctl_path" || -z "$visudo_path" ]]; then
    info "Installing brightness permission prerequisites."
    install_packages brightnessctl sudo || warn "Could not install brightnessctl and sudo; brightness permissions were skipped."
  fi
  brightnessctl_path="$(command -v brightnessctl 2>/dev/null || true)"
  [[ -x /usr/bin/brightnessctl ]] && brightnessctl_path=/usr/bin/brightnessctl
  visudo_path="$(command -v visudo 2>/dev/null || true)"
  [[ -x /usr/sbin/visudo ]] && visudo_path=/usr/sbin/visudo
  if [[ -z "$brightnessctl_path" || -z "$visudo_path" ]]; then
    warn "brightnessctl or visudo is unavailable; passwordless brightness control was not configured."
    return 1
  fi
  getent group "$group" >/dev/null 2>&1 || {
    warn "The video group is unavailable; brightness permissions were not configured."
    return 1
  }

  if ! id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$group"; then
    run_as_root usermod -aG "$group" "$TARGET_USER" || {
      warn "Could not add $TARGET_USER to the video group; brightness changes may require sudo."
      return 1
    }
    SETUP_RELOGIN_REQUIRED=1
    info "$TARGET_USER added to video; log out and back in for the group change to apply."
  fi

  temp_file="$(run_as_root mktemp /etc/udev/rules.d/.startup-backlight.XXXXXX)" || {
    warn "Could not prepare the backlight udev rule."
    return 1
  }
  if ! printf '%s\n' \
    'SUBSYSTEM=="backlight", ACTION=="add", TAG+="uaccess", GROUP="video", MODE="0664"' \
    'SUBSYSTEM=="leds", KERNEL=="*kbd_backlight*", ACTION=="add", TAG+="uaccess", GROUP="video", MODE="0664"' \
    | run_as_root tee "$temp_file" >/dev/null; then
    run_as_root rm -f -- "$temp_file"
    warn "Could not write the backlight udev rule."
    return 1
  fi
  run_as_root chmod 644 "$temp_file" && run_as_root mv -f -- "$temp_file" "$rule_file" || {
    run_as_root rm -f -- "$temp_file"
    warn "Could not install $rule_file."
    return 1
  }
  if command -v udevadm >/dev/null 2>&1; then
    run_as_root udevadm control --reload-rules >>"$SETUP_LOG_FILE" 2>&1 || warn "Could not reload udev rules."
    run_as_root udevadm trigger --subsystem-match=backlight >>"$SETUP_LOG_FILE" 2>&1 || true
    run_as_root udevadm trigger --subsystem-match=leds >>"$SETUP_LOG_FILE" 2>&1 || true
  fi

  # Sway keybindings cannot answer an invisible sudo password prompt.  Allow
  # only the brightnessctl binary for this user, and validate the rule before
  # installing it.  Volume and other session controls remain unprivileged.
  if [[ -n "$visudo_path" && -n "$brightnessctl_path" ]]; then
    run_as_root install -d -m 755 /etc/sudoers.d || {
      warn "Could not create /etc/sudoers.d for the brightness rule."
      return 1
    }
    sudoers_temp="$(run_as_root mktemp /etc/sudoers.d/.startup-brightness.XXXXXX)" || {
      warn "Could not prepare the brightness sudoers rule."
      return 1
    }
    if ! printf '%s ALL=(root) NOPASSWD: %s\n' "$TARGET_USER" "$brightnessctl_path" | run_as_root tee "$sudoers_temp" >/dev/null; then
      run_as_root rm -f -- "$sudoers_temp"
      warn "Could not write the brightness sudoers rule."
      return 1
    fi
    run_as_root chmod 440 "$sudoers_temp"
    if run_as_root "$visudo_path" -cf "$sudoers_temp" >>"$SETUP_LOG_FILE" 2>&1; then
      run_as_root mv -f -- "$sudoers_temp" "$sudoers_file"
    else
      run_as_root rm -f -- "$sudoers_temp"
      warn "The generated brightness sudoers rule failed validation."
      return 1
    fi
  fi
  ok "Brightness device permissions configured"
}

copy_tree_with_backup() {
  local src dest label announce backup relative
  src="${1:-}"; dest="${2:-}"; label="${3:-configuration}"; announce="${4:-1}"
  if [[ -z "$src" || -z "$dest" ]]; then warn "$label copy requested with a missing source or destination"; return 1; fi
  if [[ "$dest" != "$TARGET_HOME"/* || "$dest" == "$TARGET_HOME" ]]; then warn "$label destination is outside the target home and was refused: $dest"; return 1; fi
  if [[ ! -d "$src" ]]; then warn "$label source is missing: $src — skipped"; return 0; fi
  if find "$src" -xtype l -print -quit | grep -q .; then warn "$label contains broken symbolic links — skipped"; return 0; fi
  relative="${dest#"$TARGET_HOME"/}"; backup="$SETUP_BACKUP_DIR/files/$relative"
  if [[ -e "$dest" || -L "$dest" ]]; then
    if ! run_as_root install -d -m 700 "$(dirname "$backup")" || ! run_as_root cp -a "$dest" "$backup"; then warn "$label could not be backed up; leaving it unchanged"; return 1; fi
  fi
  # Validate the source before removing the current installation.  A parser
  # failure must never leave the user with an empty configuration directory.
  if ! validate_managed_tree "$src" "$label"; then warn "$label source failed validation; target was not changed"; return 1; fi
  if [[ -e "$dest" || -L "$dest" ]]; then
    if ! run_as_root rm -rf --one-file-system "$dest"; then warn "$label could not remove the old target"; return 1; fi
  fi
  if ! ensure_directory "$dest" 755 || ! run_as_root cp -a "$src/." "$dest/"; then warn "$label could not be copied"; return 1; fi
  if ! validate_managed_tree "$dest" "$label"; then
    warn "$label failed validation after installation; restoring its backup"
    run_as_root rm -rf --one-file-system "$dest"
    [[ -e "$backup" ]] && run_as_root cp -a "$backup" "$dest"
    return 1
  fi
  [[ "$announce" == "0" ]] || ok "$label installed"
}

# Shell features live in one POSIX-compatible file so Bash and Zsh always
# receive identical aliases, helpers, editor defaults, and emergency controls.
# Shell-specific prompt/completion setup is installed as a small loader block.
shell_shared_features_content() {
  cat <<'EOF'
# Managed by startup: shared Bash/Zsh shell features.
# This file intentionally uses syntax accepted by both Bash and Zsh.

export EDITOR="${EDITOR:-nano}"
export VISUAL="${VISUAL:-$EDITOR}"

alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias c='clear'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'

# Existing project conveniences, shared rather than Zsh-only.
alias startpro='mkdir -p ~/pro/{ctf/{htb/{challenges,machines,sherlocks,start,vpn},{thm/{vpn,machines}}},proje,repo}'
alias pro='cd ~/pro'
alias ctf='cd ~/pro/ctf'
alias htb='cd ~/pro/ctf/htb'
alias htbvpn='cd ~/pro/ctf/htb/vpn'
alias thm='cd ~/pro/ctf/thm'
alias thmvpn='cd ~/pro/ctf/thm/vpn'
alias proje='cd ~/pro/proje'
alias repo='cd ~/pro/repo'
alias by='systemctl poweroff'
alias zz='systemctl suspend'
alias rb='systemctl reboot'

doomnow_state_dir() {
  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/neo"
}

doomnow_state_file() {
  printf '%s/doomnow-processes.tsv\n' "$(doomnow_state_dir)"
}

# Only executable names in this allow-list are selected.  Deliberately do not
# match shells, terminal emulators, compositors, NetworkManager, or services.
doomnow_list_processes() {
  command ps -u "$(id -u)" -o pid= -o comm= -o args= 2>/dev/null |
    awk -v self="$$" -v parent="${PPID:-0}" '
      $1 != self && $1 != parent &&
      $2 ~ /^(python|python[0-9.]*|node|npm|npx|yarn|pnpm|perl|ruby|cargo|go|pip|pip[0-9.]*|pipx|uv|poetry|pytest|flask|django|uvicorn|gunicorn|php|java|gradle|mvn|dotnet)$/ {
        pid=$1
        $1=""; $2=""
        sub(/^[[:space:]]+/, "")
        print pid "\t" $0
      }
    '
}

doomnow_network_status() {
  command -v nmcli >/dev/null 2>&1 || return 0
  printf '[NET] Wi-Fi: %s; networking: %s\n' \
    "$(nmcli radio wifi 2>/dev/null || printf 'unknown')" \
    "$(nmcli networking 2>/dev/null || printf 'unknown')"
}

doomnow() {
  doom_state_dir="$(doomnow_state_dir)"
  doom_state_file="$(doomnow_state_file)"
  doom_candidates=""
  doom_state_tmp=""
  mkdir -p "$doom_state_dir" 2>/dev/null || {
    printf '[DOOMNOW] Cannot create state directory: %s\n' "$doom_state_dir" >&2
    return 1
  }
  doom_candidates="$(mktemp "$doom_state_dir/.doomnow-candidates.XXXXXX")" || return 1
  doom_state_tmp="$(mktemp "$doom_state_dir/.doomnow-state.XXXXXX")" || {
    rm -f -- "$doom_candidates"
    return 1
  }

  printf '[DOOMNOW] Emergency development-session shutdown initiated...\n'
  if command -v nmcli >/dev/null 2>&1; then
    printf '[NET] Disabling Wi-Fi and NetworkManager networking...\n'
    nmcli radio wifi off >/dev/null 2>&1 || printf '[WARN] Could not disable Wi-Fi.\n' >&2
    nmcli networking off >/dev/null 2>&1 || printf '[WARN] Could not disable networking.\n' >&2
  else
    printf '[NET] nmcli is unavailable; networking was not changed.\n'
  fi
  doomnow_network_status

  doomnow_list_processes >"$doom_candidates"
  printf '# doomnow state; development processes require manual restart\n' >"$doom_state_tmp"
  while IFS="$(printf '\t')" read -r doom_pid doom_command; do
    [ -n "$doom_pid" ] || continue
    doom_cwd="$(readlink "/proc/$doom_pid/cwd" 2>/dev/null || printf 'unknown')"
    printf '%s\t%s\t%s\n' "$doom_pid" "$doom_cwd" "$doom_command" >>"$doom_state_tmp"
  done <"$doom_candidates"
  mv -f -- "$doom_state_tmp" "$doom_state_file"

  doom_count="$(wc -l <"$doom_candidates" | tr -d '[:space:]')"
  if [ "$doom_count" -gt 0 ] 2>/dev/null; then
    printf '[KILL] Found %s development/runtime process(es):\n' "$doom_count"
    while IFS="$(printf '\t')" read -r doom_pid doom_command; do
      printf '  PID %s %s\n' "$doom_pid" "$doom_command"
    done <"$doom_candidates"
    printf '[TERM] Sending SIGTERM...\n'
    while IFS="$(printf '\t')" read -r doom_pid doom_command; do
      kill -TERM "$doom_pid" 2>/dev/null || true
    done <"$doom_candidates"
    sleep 2
    doomnow_list_processes >"$doom_candidates"
    doom_count="$(wc -l <"$doom_candidates" | tr -d '[:space:]')"
    if [ "$doom_count" -gt 0 ] 2>/dev/null; then
      printf '[KILL] Force-killing %s remaining survivor(s)...\n' "$doom_count"
      while IFS="$(printf '\t')" read -r doom_pid doom_command; do
        kill -KILL "$doom_pid" 2>/dev/null || true
      done <"$doom_candidates"
      sleep 1
    fi
  else
    printf '[KILL] No matching development/runtime processes found.\n'
  fi
  doomnow_list_processes >"$doom_candidates"
  doom_count="$(wc -l <"$doom_candidates" | tr -d '[:space:]')"
  rm -f -- "$doom_candidates"
  if [ "$doom_count" -gt 0 ] 2>/dev/null; then
    printf '[WARN] %s matching process(es) remain; inspect %s\n' "$doom_count" "$doom_state_file" >&2
  else
    printf '[OK] Development processes terminated.\n'
  fi
  DOOMNOW_ACTIVE=1
  export DOOMNOW_ACTIVE
  printf '[DOOMNOW] Emergency shutdown is active. Networking and selected user processes are stopped.\n'
}

doomup() {
  doom_state_file="$(doomnow_state_file)"
  printf '[DOOMUP] Restoring networking and safe user services...\n'
  if command -v nmcli >/dev/null 2>&1; then
    nmcli networking on >/dev/null 2>&1 || printf '[WARN] Could not enable networking.\n' >&2
    nmcli radio wifi on >/dev/null 2>&1 || printf '[WARN] Could not enable Wi-Fi.\n' >&2
    sleep 2
    doomnow_network_status
  else
    printf '[NET] nmcli is unavailable; networking must be restored by the active network manager.\n'
  fi
  if command -v systemctl >/dev/null 2>&1; then
    for doom_unit in pipewire.service pipewire-pulse.service wireplumber.service; do
      doom_load_state="$(systemctl --user show --property=LoadState --value "$doom_unit" 2>/dev/null || true)"
      [ "$doom_load_state" = loaded ] || continue
      if systemctl --user try-restart "$doom_unit" >/dev/null 2>&1; then
        printf '[SERVICE] Checked %s\n' "$doom_unit"
      else
        printf '[WARN] Could not restart %s; it may not have an active user session.\n' "$doom_unit" >&2
      fi
    done
  else
    printf '[SERVICE] systemctl is unavailable; user services were not changed.\n'
  fi
  unset DOOMNOW_ACTIVE
  if [ -s "$doom_state_file" ]; then
    printf '[INFO] Captured process details are in %s\n' "$doom_state_file"
    printf '[INFO] Development processes are not restarted automatically; their original launch context cannot be reconstructed safely.\n'
  fi
  printf '[DOOMUP] Network restoration complete.\n'
}
EOF
}

shell_bash_loader_content() {
  cat <<'EOF'
# >>> startup shell features >>>
# Shared aliases/functions are installed separately to keep Bash and Zsh equal.
[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/startup/shell-common.sh" ] && . "${XDG_CONFIG_HOME:-$HOME/.config}/startup/shell-common.sh"
# <<< startup shell features <<<
EOF
}

shell_zsh_loader_content() {
  cat <<'EOF'
# >>> startup shell features >>>
[[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/startup/shell-common.sh" ]] && source "${XDG_CONFIG_HOME:-$HOME/.config}/startup/shell-common.sh"

# Managed interactive Zsh configuration, based on the project profile.
setopt autocd interactivecomments magicequalsubst nonomatch notify numericglobsort promptsubst
WORDCHARS='_-'
PROMPT_EOL_MARK=""
bindkey -e
bindkey ' ' magic-space
bindkey '^U' backward-kill-line
bindkey '^[[3;5~' kill-word
bindkey '^[[3~' delete-char
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[5~' beginning-of-buffer-or-history
bindkey '^[[6~' end-of-buffer-or-history
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[Z' undo

autoload -Uz compinit
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}" 2>/dev/null
compinit -i -d "${XDG_CACHE_HOME:-$HOME/.cache}/zcompdump"
zstyle ':completion:*:*:*:*:*' menu select
zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' list-prompt %SAt\ %p:\ Hit\ TAB\ for\ more%s
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' rehash true
zstyle ':completion:*' select-prompt %SScrolling\ active:\ current\ selection\ at\ %p%s
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

HISTFILE="$HOME/.zsh_history"
HISTSIZE=1000
SAVEHIST=2000
setopt hist_expire_dups_first hist_ignore_dups hist_ignore_space hist_verify
alias history='history 0'
TIMEFMT=$'\nreal\t%E\nuser\t%U\nsys\t%S\ncpu\t%P'

if [[ -z "${debian_chroot:-}" && -r /etc/debian_chroot ]]; then debian_chroot="$(cat /etc/debian_chroot)"; fi
case "$TERM" in xterm-color|*-256color) color_prompt=yes;; esac
if [[ -x /usr/bin/tput ]] && tput setaf 1 >&/dev/null; then color_prompt=yes; else color_prompt=; fi

configure_prompt() {
  local prompt_symbol='㉿'
  case "$PROMPT_ALTERNATIVE" in
    twoline) PROMPT=$'%F{%(#.blue.green)}┌──${debian_chroot:+($debian_chroot─)}${VIRTUAL_ENV:+($(basename $VIRTUAL_ENV)─)}(%B%F{%(#.red.blue)}%n'$prompt_symbol$'%m%b%F{%(#.blue.green)})-[%B%F{reset}%(6~.%-1~/…/%4~.%5~)%b%F{%(#.blue.green)}]\n└─%B%(#.%F{red}#.%F{blue}$)%b%F{reset} ';;
    oneline) PROMPT=$'${debian_chroot:+($debian_chroot)}${VIRTUAL_ENV:+($(basename $VIRTUAL_ENV))}%B%F{%(#.red.blue)}%n@%m%b%F{reset}:%B%F{%(#.blue.green)}%~%b%F{reset}%(#.#.$) '; RPROMPT=;;
    backtrack) PROMPT=$'${debian_chroot:+($debian_chroot)}${VIRTUAL_ENV:+($(basename $VIRTUAL_ENV))}%B%F{red}%n@%m%b%F{reset}:%B%F{blue}%~%b%F{reset}%(#.#.$) '; RPROMPT=;;
  esac
}
PROMPT_ALTERNATIVE=twoline
NEWLINE_BEFORE_PROMPT=yes
VIRTUAL_ENV_DISABLE_PROMPT=1
configure_prompt
toggle_oneline_prompt() { [[ "$PROMPT_ALTERNATIVE" == oneline ]] && PROMPT_ALTERNATIVE=twoline || PROMPT_ALTERNATIVE=oneline; configure_prompt; zle reset-prompt; }
zle -N toggle_oneline_prompt
bindkey ^P toggle_oneline_prompt
case "$TERM" in xterm*|rxvt*|Eterm|aterm|kterm|gnome*|alacritty) TERM_TITLE=$'\e]0;${debian_chroot:+($debian_chroot)}${VIRTUAL_ENV:+($(basename $VIRTUAL_ENV))}%n@%m: %~\a';; esac
precmd() { print -Pnr -- "$TERM_TITLE"; if [[ "$NEWLINE_BEFORE_PROMPT" == yes ]]; then [[ -n "${_NEW_LINE_BEFORE_PROMPT:-}" ]] && print ""; _NEW_LINE_BEFORE_PROMPT=1; fi; }

if [[ -x /usr/bin/dircolors ]]; then
  [[ -r ~/.dircolors ]] && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
  export LS_COLORS="$LS_COLORS:ow=30;44:"
  alias ls='ls --color=auto' grep='grep --color=auto' fgrep='fgrep --color=auto' egrep='egrep --color=auto' diff='diff --color=auto' ip='ip --color=auto'
  export LESS_TERMCAP_mb=$'\E[1;31m' LESS_TERMCAP_md=$'\E[1;36m' LESS_TERMCAP_me=$'\E[0m' LESS_TERMCAP_so=$'\E[01;33m' LESS_TERMCAP_se=$'\E[0m' LESS_TERMCAP_us=$'\E[1;32m' LESS_TERMCAP_ue=$'\E[0m' MANROFFOPT='-c'
  zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
fi
if [[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern); ZSH_HIGHLIGHT_STYLES[unknown-token]=underline; ZSH_HIGHLIGHT_STYLES[reserved-word]=fg=cyan,bold; ZSH_HIGHLIGHT_STYLES[arg0]=fg=cyan; ZSH_HIGHLIGHT_STYLES[bracket-error]=fg=red,bold; fi
if [[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh; ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=244'; fi
[[ -f /etc/zsh_command_not_found ]] && source /etc/zsh_command_not_found
# <<< startup shell features <<<
EOF
}

install_shell_loader() {
  local rc_file="$1" shell_name="$2" temp source_temp backup_dir
  temp="$SETUP_RUNTIME_DIR/${shell_name}rc.$$"
  source_temp="$SETUP_RUNTIME_DIR/${shell_name}rc-source.$$"
  if [[ -f "$rc_file" ]]; then
    run_as_root cat -- "$rc_file" >"$source_temp" || return 1
  else
    : >"$source_temp"
  fi
  # Remove our previous managed block and the exact legacy project fragment;
  # unrelated user configuration remains byte-for-byte in place.
  awk '
    /^# >>> startup shell features >>>$/ { managed=1; next }
    /^# <<< startup shell features <<<$/ { managed=0; next }
    /^alias startpro='\''mkdir -p ~\/pro\/\{ctf\// { legacy=1; next }
    legacy && /^doomnow\(\) \{/ { legacy_doom=1; next }
    legacy && legacy_doom && /^}$/ { legacy=0; legacy_doom=0; next }
    managed || legacy { next }
    { print }
  ' "$source_temp" >"$temp" || { rm -f -- "$temp" "$source_temp"; return 1; }
  if [[ -s "$temp" ]] && [[ "$(tail -c 1 "$temp" 2>/dev/null || true)" != $'\n' ]]; then printf '\n' >>"$temp"; fi
  if [[ "$shell_name" == bash ]]; then shell_bash_loader_content >>"$temp"; else shell_zsh_loader_content >>"$temp"; fi
  backup_dir="$SETUP_BACKUP_DIR/shell-config"
  if [[ -f "$rc_file" ]] && ! cmp -s "$temp" "$rc_file"; then
    run_as_root install -d -m 700 "$backup_dir" || return 1
    run_as_root cp -a -- "$rc_file" "$backup_dir/$(basename "$rc_file").bak" || return 1
    _setup_log_write INFO "Backed up $rc_file to $backup_dir"
  fi
  if ! cmp -s "$temp" "$rc_file" 2>/dev/null; then
    run_as_root install -o "$TARGET_USER" -g "$TARGET_GROUP" -m 644 "$temp" "$rc_file" || { rm -f -- "$temp" "$source_temp"; return 1; }
    _setup_log_write INFO "Installed managed $shell_name loader in $rc_file"
  fi
  rm -f -- "$temp" "$source_temp"
}

install_shell_configuration() {
  local config_home="$TARGET_HOME/.config" shared_file="$TARGET_HOME/.config/startup/shell-common.sh" temp
  temp="$SETUP_RUNTIME_DIR/shell-common.$$"
  shell_shared_features_content >"$temp" || return 1
  run_as_root install -d -o "$TARGET_USER" -g "$TARGET_GROUP" -m 755 "$config_home/startup" || return 1
  if [[ ! -f "$shared_file" ]] || ! cmp -s "$temp" "$shared_file"; then
    run_as_root install -o "$TARGET_USER" -g "$TARGET_GROUP" -m 644 "$temp" "$shared_file" || { rm -f -- "$temp"; return 1; }
    _setup_log_write INFO "Installed shared shell features: $shared_file"
  fi
  rm -f -- "$temp"
  install_shell_loader "$TARGET_HOME/.bashrc" bash || return 1
  install_shell_loader "$TARGET_HOME/.zshrc" zsh || return 1
  ok "Shared Bash/Zsh aliases and emergency helpers installed"
}

run_config_files() {
  main_sep
  [[ -d "$SCRIPT_DIR/sway" ]] || { warn "sway resource directory is missing; skipping configuration."; return 0; }
  fix_project_script_permissions "$SCRIPT_DIR"

  local failed=0 target
  copy_tree_with_backup "$SCRIPT_DIR/sway/.config/foot" "$TARGET_HOME/.config/foot" "Foot configuration" 0 || failed=1
  if [[ -f "$TARGET_HOME/.config/foot/foot.ini" && "${DISTRO_ID:-}" != kali ]]; then
    run_as_root sed -i 's/^\[colors-dark\]$/[colors]/' "$TARGET_HOME/.config/foot/foot.ini" || warn "Could not select the Debian Foot color section"
  fi
  copy_tree_with_backup "$SCRIPT_DIR/sway/.config/i3blocks" "$TARGET_HOME/.config/i3blocks" "i3blocks configuration" 0 || failed=1
  copy_tree_with_backup "$SCRIPT_DIR/sway/.config/sway" "$TARGET_HOME/.config/sway" "Sway configuration" 0 || failed=1
  copy_tree_with_backup "$SCRIPT_DIR/sway/.config/flameshot" "$TARGET_HOME/.config/flameshot" "Flameshot configuration" 0 || failed=1
  copy_tree_with_backup "$SCRIPT_DIR/sway/.config/wofi" "$TARGET_HOME/.config/wofi" "Wofi configuration" 0 || failed=1
  copy_tree_with_backup "$SCRIPT_DIR/sway/.config/systemd" "$TARGET_HOME/.config/systemd" "User systemd units" 0 || failed=1
  (( failed == 0 )) && ok ".config files copied" || warn "Some .config resources were not copied; existing files were preserved."

  main_sep
  copy_tree_with_backup "$SCRIPT_DIR/sway/.local/bin" "$TARGET_HOME/.local/bin" "User commands" 0 || failed=1
  (( failed == 0 )) && ok ".local/bin files copied" || warn "Some user commands were not copied."

  main_sep
  copy_tree_with_backup "$SCRIPT_DIR/sway/.local/share/fonts" "$TARGET_HOME/.local/share/fonts" "Fonts" 0 || failed=1
  if [[ -d "$SCRIPT_DIR/sway/.local/share/fonts" ]]; then
    run_as_target fc-cache -f "$TARGET_HOME/.local/share/fonts" >/dev/null 2>&1 || warn "Font cache refresh failed; it will refresh on next login."
  fi
  (( failed == 0 )) && ok "Fonts copied and cache refreshed" || warn "Some fonts or managed configuration files were not installed."

  main_sep
  for target in "$TARGET_HOME/.config/foot" "$TARGET_HOME/.config/i3blocks" "$TARGET_HOME/.config/sway" "$TARGET_HOME/.config/flameshot" "$TARGET_HOME/.config/wofi" "$TARGET_HOME/.config/systemd" "$TARGET_HOME/.local/bin" "$TARGET_HOME/.local/share/fonts"; do
    [[ -d "$target" ]] || continue
    run_as_root chown -R "$TARGET_USER:$TARGET_GROUP" "$target" || warn "Could not fix ownership under $target"
    fix_tree_permissions "$target" 644 || warn "Could not fix permissions under $target"
  done
  configure_backlight_access || true
  ok "Permissions updated"

  install_shell_configuration || warn "Could not install the shared Bash/Zsh shell configuration."

  # Preserve the project's existing intent: when zsh is installed, register it
  # in /etc/shells and make it the target user's login shell.
  if command -v zsh >/dev/null 2>&1; then
    local zsh_path
    zsh_path="$(command -v zsh)"
    if ! run_as_root grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
      printf '%s\n' "$zsh_path" | run_as_root tee -a /etc/shells >/dev/null || warn "Could not add $zsh_path to /etc/shells"
    fi
    if run_as_root chsh -s "$zsh_path" "$TARGET_USER"; then
      if [[ "$(getent passwd "$TARGET_USER" | cut -d: -f7)" == "$zsh_path" ]]; then
        ok "Default shell for $TARGET_USER set to zsh"
      else
        warn "zsh was requested as the default shell for $TARGET_USER but could not be verified"
      fi
    else
      warn "Could not change default shell to zsh for $TARGET_USER"
    fi
  else
    info "zsh is unavailable; .zshrc was generated for use when zsh is installed."
  fi
}
