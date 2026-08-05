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
}
