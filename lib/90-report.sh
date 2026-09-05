#!/usr/bin/env bash
# ==================================================
# 90-report.sh
# Final report, short Sway preview, and completion banner.
# ==================================================

if [[ -n "${__SETUP_REPORT_LOADED:-}" ]]; then return 0; fi
__SETUP_REPORT_LOADED=1


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

# Returns success only when the user sends keyboard or pointer input to the
# nested Sway window during its short preview grace period.
preview_sway_window_interacted() {
  local window="$1" awk_status
  command -v xev >/dev/null 2>&1 || { sleep 3; return 1; }
  run_as_target env DISPLAY="$DISPLAY" timeout --foreground 3s \
    xev -id "$window" -event keyboard -event mouse 2>/dev/null |
    awk '/^(KeyPress|KeyRelease|ButtonPress|ButtonRelease|MotionNotify) event/ { interacted=1; exit } END { exit !interacted }'
  # xev receives SIGPIPE once awk has seen an interaction.  Its status is
  # irrelevant; only awk's interaction result determines the preview action.
  awk_status="${PIPESTATUS[1]}"
  return "$awk_status"
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
  local preview_launcher_pid preview_pid preview_window attempt preview_closed_by_timeout=0
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
  info 'Sway preview opens for 3 seconds and closes automatically unless you interact with its window.'
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

  if [[ -n "$preview_window" ]] && preview_sway_window_interacted "$preview_window"; then
    info 'Sway preview interaction detected; close the preview window when finished.'
  else
    info 'No Sway preview interaction detected after 3 seconds; closing the preview.'
    preview_closed_by_timeout=1
    [[ -n "$preview_pid" ]] && kill -TERM "$preview_pid" 2>/dev/null || true
    kill -TERM "$preview_launcher_pid" 2>/dev/null || true
  fi

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
  if (( rc != 0 && preview_closed_by_timeout == 0 )); then
    warn "Sway preview could not be completed; see $SETUP_LOG_FILE"
  fi
  return 0
}

launch_final_sway() {
  launch_sway_preview "$@"
}

# ---------- Orchestration ----------
run_report() {
  # Preserve the existing single automatic Sway reload before the preview.
  reload_target_sway || true

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
  echo "Aliases      : ll, la, gs, ga, gc, gp, gl, pro, ctf, repo"
  echo "Backups      :"
  [[ -d "${SETUP_BACKUP_DIR:-}" ]] && echo "  Installer  : $SETUP_BACKUP_DIR"
  [[ -d "${SETUP_WALLPAPER_BACKUP_DIR:-}" ]] && echo "  Wallpapers : $SETUP_WALLPAPER_BACKUP_DIR"
  [[ -d "${security_backup_dir:-}" ]] && echo "  Security   : $security_backup_dir"
  printf '%s================================================================================%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"

  # Sway is launched by the user's session configuration, never by the
  # installer. This prevents a background compositor from keeping the
  # installer terminal attached after the report has finished.

}
