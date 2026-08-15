#!/usr/bin/env bash
# ==================================================
# 90-report.sh
# Final "Setup completed" banner + interactive install
# script picker (only install_*.sh files) + completion banner.
# ==================================================

if [[ -n "${__SETUP_REPORT_LOADED:-}" ]]; then return 0; fi
__SETUP_REPORT_LOADED=1

optional_command_installed() {
  local command_name="${1:-}"
  command -v "$command_name" >/dev/null 2>&1 || [[ -x "$TARGET_HOME/.local/bin/$command_name" ]]
}

preview_sway_pid() {
  local pid environ
  while read -r pid; do
    [[ -r "/proc/$pid/environ" ]] || continue
    environ="$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null || true)"
    [[ "$environ" == *'STARTUP_SWAY_PREVIEW=1'* ]] && { printf '%s\n' "$pid"; return 0; }
  done < <(pgrep -u "$TARGET_UID" -x sway 2>/dev/null || true)
  return 1
}

preview_sway_window() {
  local sway_pid="$1" window owner
  command -v xprop >/dev/null 2>&1 || return 1
  while read -r window; do
    owner="$(run_as_target env DISPLAY="$DISPLAY" xprop -id "$window" _NET_WM_PID 2>/dev/null || true)"
    [[ "$owner" =~ =\ *"$sway_pid"$ ]] && { printf '%s\n' "$window"; return 0; }
  done < <(run_as_target env DISPLAY="$DISPLAY" xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -oE '0x[[:xdigit:]]+' || true)
  return 1
}

# The user explicitly wants this exact command attempted at the end of every
# installer invocation, including a run that completed with reported issues.
# The guard lets the EXIT cleanup path serve as a backup without launching two
# nested compositors during a normal run.
launch_sway_preview() {
  (( SETUP_FINAL_SWAY_LAUNCHED == 0 )) || return 0
  SETUP_FINAL_SWAY_LAUNCHED=1
  command -v sway >/dev/null 2>&1 || { warn 'Sway preview could not open: sway is not installed.'; return 0; }
  if [[ -z "${DISPLAY:-}" ]]; then
    warn 'Sway preview could not open: X11 DISPLAY is unavailable for WLR_BACKENDS=x11.'
    return 0
  fi

  # Remove only previews created by this installer (identified by their
  # nested X11 wlroots environment).  Never terminate the user's real desktop
  # Sway session.
  local pid environ preview_config rc target_config proc_name preview_wallpaper candidate
  local preview_launcher_pid preview_pid preview_window attempt
  for proc_name in sway swayidle swaylock swaybg i3blocks foot wofi; do
    while read -r pid; do
      [[ -r "/proc/$pid/environ" ]] || continue
      environ="$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null || true)"
      [[ "$environ" == *'STARTUP_SWAY_PREVIEW=1'* ]] || continue
      kill -TERM "$pid" 2>/dev/null || true
    done < <(pgrep -u "$TARGET_UID" -x "$proc_name" 2>/dev/null || true)
  done

  preview_config="$SETUP_RUNTIME_DIR/sway-preview.conf"
  mkdir -p "$SETUP_RUNTIME_DIR" 2>/dev/null || return 0
  target_config="$TARGET_HOME/.config/sway/config"
  preview_wallpaper=""
  for candidate in "$TARGET_HOME/.local/share/backgrounds/startup/IMG1.jpg" "$TARGET_HOME/.local/share/backgrounds/startup/IMG2.jpg" "$SCRIPT_DIR/wallpaper/IMG1.jpg" "$SCRIPT_DIR/wallpaper/IMG2.jpg"; do
    [[ -f "$candidate" ]] && { preview_wallpaper="$candidate"; break; }
  done
  if [[ -f "$target_config" ]]; then
    cat >"$preview_config" <<EOF
# Temporary installer preview configuration.
include $target_config
output * mode 800x600
bindsym Ctrl+Shift+q exit
EOF
  else
    cat >"$preview_config" <<'EOF'
# Temporary installer preview configuration.
output * mode 800x600
bar {
    status_command while date '+startup sway preview  %H:%M:%S'; do sleep 1; done
    position top
}
bindsym Ctrl+Shift+q exit
EOF
  fi
  if [[ -n "$preview_wallpaper" ]]; then
    printf 'output * bg "%s" fill\n' "$preview_wallpaper" >>"$preview_config"
  fi
  run_as_root chown "$TARGET_USER:$TARGET_GROUP" "$preview_config" 2>/dev/null || true
  printf '%s\n' 'To close ctrl + c in terminal or super +shift + q in the window'
  run_as_target env \
    STARTUP_SWAY_PREVIEW=1 DISPLAY="$DISPLAY" WLR_BACKENDS=x11 WLR_X11_OUTPUTS=1 WLR_X11_SCALE=1 \
    XDG_CURRENT_DESKTOP=sway XDG_SESSION_DESKTOP=sway XDG_SESSION_TYPE=wayland \
    XDG_RUNTIME_DIR="$(target_runtime_dir)" \
    sway -c "$preview_config" >>"$SETUP_LOG_FILE" 2>&1 &
  preview_launcher_pid=$!

  # wlroots can keep the nested compositor running after its X11 window has
  # been dismissed by the host desktop.  Watch that window and end only this
  # tagged preview so the installer can resume immediately on window close.
  preview_pid=""
  preview_window=""
  for ((attempt = 0; attempt < 25; attempt++)); do
    preview_pid="$(preview_sway_pid || true)"
    [[ -n "$preview_pid" ]] && preview_window="$(preview_sway_window "$preview_pid" || true)"
    [[ -n "$preview_window" ]] && break
    sleep 0.2
  done
  while kill -0 "$preview_launcher_pid" 2>/dev/null; do
    if [[ -n "$preview_window" ]] && ! run_as_target env DISPLAY="$DISPLAY" xprop -id "$preview_window" _NET_WM_PID >/dev/null 2>&1; then
      info 'Sway preview window closed; continuing setup.'
      [[ -n "$preview_pid" ]] && kill -TERM "$preview_pid" 2>/dev/null || true
      break
    fi
    sleep 0.2
  done
  wait "$preview_launcher_pid"
  rc=$?
  _setup_log_write INFO "Sway preview closed (exit $rc)."
  for proc_name in swayidle swaylock swaybg i3blocks foot wofi; do
    while read -r pid; do
      [[ -r "/proc/$pid/environ" ]] || continue
      environ="$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null || true)"
      [[ "$environ" == *'STARTUP_SWAY_PREVIEW=1'* ]] || continue
      kill -TERM "$pid" 2>/dev/null || true
    done < <(pgrep -u "$TARGET_UID" -x "$proc_name" 2>/dev/null || true)
  done
  (( rc == 0 )) || warn "Sway preview could not be completed; see $SETUP_LOG_FILE"
  return 0
}

launch_final_sway() {
  launch_sway_preview "$@"
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
  # Preserve the existing single automatic Sway reload, but complete it before
  # the portal repair so the portal repair is the final required action before
  # the optional-tools question.
  reload_target_sway || true

  # Keep the original optional-tools prompt in the report.  The installers
  # themselves are isolated; selecting one cannot change required-stage state.
  printf '%s================================================================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  printf '%sOptional tools%s\n' "$SETUP_COLOR_BOLD" "$SETUP_COLOR_RST"
  printf '%s================================================================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  if prompt_yes_no "Would you like to install the additional tools?" "n"; then
    info "Starting tools installation..."
    show_install_menu
  else
    info "Skipping"
  fi

  if (( SETUP_RELOGIN_REQUIRED )); then
    info "Log out and back in to apply the group membership changed during this run."
  fi

  # The preview is the final interactive action. The existing completion and
  # summary output is printed only after the preview Sway instance exits.
  launch_sway_preview
  printf '%s========================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  ok "Setup completed"
  printf '%s========================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"

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
  elif (( ${#SETUP_DEFERRED[@]} > 0 )); then
    info "Completed with ${#SETUP_DEFERRED[@]} deferred session action(s); see $SETUP_LOG_FILE"
  else
    ok "No installer issues detected"
  fi

  # Final completion banner with system info
  printf '%s================================================================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  if (( ${#SETUP_ISSUES[@]} > 0 )); then
    warn "Installation completed with issues"
  elif (( ${#SETUP_DEFERRED[@]} > 0 )); then
    ok "Installation completed; session-dependent actions were deferred"
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
  if (( ${#FAILED_REQUIRED_PACKAGES[@]} )); then
    printf 'Failed Packages: %s\n' "${FAILED_REQUIRED_PACKAGES[*]}"
  fi
  echo "Log file     : $SETUP_LOG_FILE"
  echo "Backups      :"
  [[ -d "${SETUP_BACKUP_DIR:-}" ]] && echo "  Installer  : $SETUP_BACKUP_DIR"
  [[ -d "${SETUP_WALLPAPER_BACKUP_DIR:-}" ]] && echo "  Wallpapers : $SETUP_WALLPAPER_BACKUP_DIR"
  [[ -d "${security_backup_dir:-}" ]] && echo "  Security   : $security_backup_dir"
  printf '%s================================================================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"

  # Sway is launched by the user's session configuration, never by the
  # installer. This prevents a background compositor from keeping the
  # installer terminal attached after the report has finished.

}
