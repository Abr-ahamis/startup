#!/usr/bin/env bash
# ==================================================
# 90-report.sh
# Final "Setup completed" banner + interactive install
# script picker (only install_*.sh files) + completion banner.
# ==================================================

if [[ -n "${__SETUP_REPORT_LOADED:-}" ]]; then return 0; fi
__SETUP_REPORT_LOADED=1

start_sway_after_setup() {
  local runtime="/run/user/$TARGET_UID" socket desktop backend sway_log="$SETUP_BASE_DIR/sway-session.log"
  local -a sway_env
  [[ -d "$runtime" ]] || runtime="${XDG_RUNTIME_DIR:-/run/user/$TARGET_UID}"
  mkdir -p -m 700 "$SETUP_BASE_DIR" 2>/dev/null || true
  desktop=" ${XDG_CURRENT_DESKTOP:-} ${DESKTOP_SESSION:-} "
  if [[ "$desktop" == *sway* || "$desktop" == *Sway* ]]; then
    socket="$(find "$runtime" -maxdepth 1 -type s -name 'sway-ipc.*.sock' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1 {print $2}')"
    if [[ -n "$socket" ]] && run_as_target env XDG_RUNTIME_DIR="$runtime" SWAYSOCK="$socket" swaymsg reload >>"$SETUP_LOG_FILE" 2>&1; then
      _setup_log_write INFO "Sway configuration reloaded successfully."
    else
      _setup_log_write WARN "Sway reload could not be verified; the active session was left untouched."
    fi
    return 0
  fi
  command -v sway >/dev/null 2>&1 || { _setup_log_write WARN "Sway is not installed; background launch was skipped."; return 0; }
  if [[ -n "${WAYLAND_DISPLAY:-}" && "${XDG_SESSION_TYPE:-}" == wayland ]]; then
    backend=wayland
  elif [[ -n "${DISPLAY:-}" ]]; then
    backend=x11
  else
    _setup_log_write INFO "No graphical compositor is available; background Sway launch was skipped."
    return 0
  fi
  [[ -d "$runtime" ]] || { _setup_log_write WARN "Sway runtime directory is unavailable: $runtime"; return 0; }
  sway_env=(env "HOME=$TARGET_HOME" "USER=$TARGET_USER" "LOGNAME=$TARGET_USER" "XDG_RUNTIME_DIR=$runtime" XDG_CURRENT_DESKTOP=sway XDG_SESSION_TYPE=wayland "WLR_BACKENDS=$backend")
  if [[ "$backend" == wayland ]]; then
    sway_env+=("WAYLAND_DISPLAY=$WAYLAND_DISPLAY" WLR_WAYLAND_OUTPUTS=1)
  else
    sway_env+=("DISPLAY=$DISPLAY" WLR_X11_OUTPUTS=1)
  fi
  _setup_log_write INFO "Starting a nested Sway window under the current desktop."
  if (( EUID == 0 )); then
    runuser -u "$TARGET_USER" -- "${sway_env[@]}" nohup setsid sway >>"$sway_log" 2>&1 </dev/null &
  else
    "${sway_env[@]}" nohup setsid sway >>"$sway_log" 2>&1 </dev/null &
  fi
  return 0
}

optional_command_installed() {
  local command_name="${1:-}"
  command -v "$command_name" >/dev/null 2>&1 || [[ -x "$TARGET_HOME/.local/bin/$command_name" ]]
}

# ---------- List install scripts (only install_*.sh) ----------
scan_install_scripts() {
  INSTALL_SCRIPTS=()
  INSTALLED_OPTIONAL_TOOLS=()
  local install_dir="$SCRIPT_DIR/install"
  if [[ ! -d "$install_dir" ]]; then
    return 0
  fi
  local f name manifest
  manifest="$SETUP_RUNTIME_DIR/optional-installers.$$"
  find "$install_dir" -maxdepth 1 -type f -name 'install_*.sh' -print0 2>/dev/null | sort -z >"$manifest" || return 1
  while IFS= read -r -d '' f; do
    [[ -f "$f" ]] || continue
    name="$(basename "$f")"
    case "$name" in
      install_brave.sh) command -v brave-browser >/dev/null 2>&1 && { INSTALLED_OPTIONAL_TOOLS+=("Brave"); continue; };;
      install_protonvpn.sh) { command -v protonvpn-app >/dev/null 2>&1 || command -v protonvpn >/dev/null 2>&1 || command -v protonvpn-cli >/dev/null 2>&1; } && { INSTALLED_OPTIONAL_TOOLS+=("Proton VPN"); continue; };;
      install_rustscan.sh) command -v rustscan >/dev/null 2>&1 && { INSTALLED_OPTIONAL_TOOLS+=("RustScan"); continue; };;
      install_telegram.sh) command -v telegram-desktop >/dev/null 2>&1 && { INSTALLED_OPTIONAL_TOOLS+=("Telegram"); continue; };;
      install_virtualbox.sh) command -v virtualbox >/dev/null 2>&1 && { INSTALLED_OPTIONAL_TOOLS+=("VirtualBox"); continue; };;
      install_vscode.sh) command -v code >/dev/null 2>&1 && { INSTALLED_OPTIONAL_TOOLS+=("VS Code"); continue; };;
      install_obsidian.sh) command -v obsidian >/dev/null 2>&1 && { INSTALLED_OPTIONAL_TOOLS+=("Obsidian"); continue; };;
      install_zen-browser.sh) command -v zen >/dev/null 2>&1 && { INSTALLED_OPTIONAL_TOOLS+=("Zen Browser"); continue; };;
      install_npmAIs.sh)
        optional_command_installed npm && INSTALLED_OPTIONAL_TOOLS+=("npm")
        optional_command_installed codex && INSTALLED_OPTIONAL_TOOLS+=("Codex CLI")
        optional_command_installed kilo && INSTALLED_OPTIONAL_TOOLS+=("Kilo CLI")
        if optional_command_installed npm && optional_command_installed codex && optional_command_installed kilo; then continue; fi
        ;;
    esac
    INSTALL_SCRIPTS+=("$f")
  done <"$manifest"
  rm -f -- "$manifest"
}

# ---------- Run a single install script ----------
run_install_script() {
  local script_path="$1"
  local script_name
  script_name="$(basename "$script_path")"

  echo
  printf '%s================================================================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  printf '%s[INFO]%s Running: %s\n' "$SETUP_COLOR_INFO" "$SETUP_COLOR_RST" "$script_name"
  printf '%s================================================================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"

  chmod +x "$script_path" 2>/dev/null || true
  if STARTUP_TARGET_USER="$TARGET_USER" STARTUP_TARGET_HOME="$TARGET_HOME" bash "$script_path"; then
    printf '%s================================================================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
    ok "$script_name completed"
    printf '%s================================================================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  else
    local rc=$?
    printf '%s================================================================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
    warn "$script_name returned exit code $rc — continuing with next script"
    printf '%s================================================================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  fi
}

# ---------- Interactive menu ----------
select_install_scripts() {
  SELECTED_INSTALL_INDICES=()
  local i choice token index found
  local -a selected=()
  while true; do
    main_sep
    printf '%sSelect optional tools%s\n\n' "$SETUP_COLOR_BOLD" "$SETUP_COLOR_RST"
    for i in "${!INSTALL_SCRIPTS[@]}"; do
      if [[ " ${selected[*]} " == *" $i "* ]]; then
        printf '  [x] %2d) %s\n' "$((i + 1))" "$(basename "${INSTALL_SCRIPTS[$i]}")"
      else
        printf '  [ ] %2d) %s\n' "$((i + 1))" "$(basename "${INSTALL_SCRIPTS[$i]}")"
      fi
    done
    printf '\nType numbers to toggle.  f = install selected, e = exit.\n'
    read -r -p 'Selection: ' choice || return 1
    case "${choice,,}" in
      e|exit|q) return 1;;
      f|finish|install)
        SELECTED_INSTALL_INDICES=("${selected[@]}")
        ((${#SELECTED_INSTALL_INDICES[@]} > 0)) && return 0
        warn 'No tools selected.'
        ;;
      *)
        for token in $choice; do
          [[ "$token" =~ ^[0-9]+$ ]] || { warn "Invalid selection: $token"; continue; }
          index=$((token - 1))
          ((index >= 0 && index < ${#INSTALL_SCRIPTS[@]})) || { warn "Selection out of range: $token"; continue; }
          found=0
          for i in "${!selected[@]}"; do
            if [[ "${selected[$i]}" == "$index" ]]; then unset 'selected[i]'; found=1; break; fi
          done
          ((found == 0)) && selected+=("$index")
        done
        selected=("${selected[@]}")
        ;;
    esac
  done
}

show_install_menu() {
  scan_install_scripts

  if (( ${#INSTALLED_OPTIONAL_TOOLS[@]} )); then
    info "Already installed applications:"
    local tool
    for tool in "${INSTALLED_OPTIONAL_TOOLS[@]}"; do
      printf '  %s[ OK ]%s %s installed\n' "$SETUP_COLOR_OK" "$SETUP_COLOR_RST" "$tool"
    done
  fi

  if (( ${#INSTALL_SCRIPTS[@]} == 0 )); then
    ok "All optional applications are already installed."
    return 0
  fi

  if [[ "${SETUP_AUTO_YES:-0}" == "1" ]]; then
    info "AUTO-YES mode: running all ${#INSTALL_SCRIPTS[@]} optional installers."
    local auto_script
    for auto_script in "${INSTALL_SCRIPTS[@]}"; do
      run_install_script "$auto_script"
    done
    return 0
  fi


  while true; do
    if ! select_install_scripts; then
      info "Skipping optional tools installation."
      return 0
    fi
    info "Running ${#SELECTED_INSTALL_INDICES[@]} selected installer(s)..."
    local idx
    for idx in "${SELECTED_INSTALL_INDICES[@]}"; do run_install_script "${INSTALL_SCRIPTS[$idx]}"; done
    scan_install_scripts
    if ! prompt_yes_no "Install more optional tools?" "n"; then
      info "Remaining optional tools were not installed."
      return 0
    fi
  done
}

# ---------- Orchestration ----------
run_report() {
  # Setup completed banner
  printf '%s========================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  ok "Setup completed"
  printf '%s========================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"

  if [[ "${SETUP_CREATE_PRO:-0}" == "1" ]]; then
    run_users
  fi

  reload_target_sway || true

  # Optional tools menu

  printf '%s================================================================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  printf '%sOptional tools%s\n' "$SETUP_COLOR_BOLD" "$SETUP_COLOR_RST"
  printf '%s================================================================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"

  if prompt_yes_no "Would you like to install the additional tools?" "n"; then
    info "Starting tools installation..."
    show_install_menu
  else
    info "Skipping"
  fi

  info "Restart is not automatic. Log out and back in to apply group and user-service changes."

  main_sep
  if (( ${#SETUP_ISSUES[@]} > 0 )); then
    printf '%s[WARN]%s Completed with %d issue(s); review these first:\n' \
      "$SETUP_COLOR_WARN" "$SETUP_COLOR_RST" "${#SETUP_ISSUES[@]}"
    _setup_log_write WARN "Completed with ${#SETUP_ISSUES[@]} issue(s); review these first"
    local issue issue_count=0
    for issue in "${SETUP_ISSUES[@]}"; do
      printf '  %s\n' "$issue"
      issue_count=$((issue_count + 1))
      (( issue_count >= 12 )) && break
    done
    (( ${#SETUP_ISSUES[@]} > 12 )) && info "Additional issues are recorded in $SETUP_LOG_FILE"
  else
    ok "No installer issues detected"
  fi

  # Final completion banner with system info
  printf '%s================================================================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  if (( ${#SETUP_ISSUES[@]} > 0 )); then
    warn "Installation completed with issues"
  else
    ok "Installation completed successfully!"
  fi
  printf '%s================================================================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  echo "Target User  : $TARGET_USER"
  echo "Target Home  : $TARGET_HOME"
  echo "Distro       : ${DISTRO_PRETTY:-Unknown} ($PKG_MANAGER)"
  echo "Config Path  : $TARGET_HOME/.config"
  echo "Fonts Cached : Yes"
  echo "Wallpapers   : ${#replaced[@]} replaced"
  echo "Log file     : $SETUP_BASE_DIR/"
  printf '%s================================================================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"

  # Reload the active Sway session, or open a nested wlroots window when the
  # installer is being run from another graphical desktop.
  start_sway_after_setup || true
}
