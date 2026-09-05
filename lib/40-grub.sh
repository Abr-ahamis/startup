#!/usr/bin/env bash
# Installs the bundled theme without replacing the system GRUB directory.

if [[ -n "${__SETUP_GRUB_LOADED:-}" ]]; then return 0; fi
__SETUP_GRUB_LOADED=1

install_grub_theme() {
  local src="$SCRIPT_DIR/grub" dest="/boot/grub/themes/startup" defaults="/etc/default/grub" theme_backup
  [[ "${DISTRO_ID:-}" == kali ]] && dest="/usr/share/grub/themes/kali"
  if [[ ! -f "$src/theme.txt" || ! -f "$src/grub-16x9.png" ]]; then error "GRUB theme assets are incomplete: $src"; return 1; fi
  if [[ ! -d /boot/grub ]]; then error "/boot/grub is unavailable; cannot install the GRUB theme."; return 1; fi
  if [[ ! -f "$defaults" ]]; then run_as_root install -m 644 /dev/null "$defaults" || { error "Cannot create $defaults"; return 1; }; fi
  run_as_root install -d -m 700 "$SETUP_BACKUP_DIR" || return 1
  run_as_root cp -a "$defaults" "$SETUP_BACKUP_DIR/grub.defaults.bak" || { error "Cannot back up $defaults"; return 1; }

  replace_or_add() {
    local key="${1:-}" value="${2:-}" replacement
    [[ -n "$key" ]] || return 1
    if run_as_root grep -q -- "^${key}=" "$defaults"; then
      # `&` has special meaning in a sed replacement; escape it so the
      # distributor expression is written literally.
      replacement="${value//\\/\\\\}"
      replacement="${replacement//&/\\&}"
      run_as_root sed -i "s|^${key}=.*|${key}=${replacement}|" "$defaults"
    else
      printf '%s=%s\n' "$key" "$value" | run_as_root tee -a "$defaults" >/dev/null
    fi
  }

  if [[ -e "$dest" || -L "$dest" ]]; then
    theme_backup="$SETUP_BACKUP_DIR/grub-theme-$(basename -- "$dest")"
    run_as_root cp -a "$dest" "$theme_backup" || { warn "Could not back up existing GRUB theme: $dest"; return 1; }
  fi
  run_as_root install -d -m 755 "$(dirname -- "$dest")" || return 1
  run_as_root rm -rf -- "$dest" || return 1
  run_as_root install -d -m 755 "$dest" || return 1
  run_as_root cp -a "$src/." "$dest/" || return 1
  run_as_root find "$dest" -type f -exec chmod 644 {} + || return 1
  run_as_root find "$dest" -type f -name '*.sh' -exec chmod 755 {} + || return 1
  replace_or_add "GRUB_THEME" "\"$dest/theme.txt\"" || return 1
  run_as_root chmod 644 "$defaults"
  # Debian keeps update-grub in grub2-common.  Install it here as a final
  # self-repair in case the package stage was skipped or previously failed.
  if ! run_as_root sh -c 'command -v update-grub >/dev/null 2>&1 || command -v grub-mkconfig >/dev/null 2>&1' && [[ "$PKG_MANAGER" == apt ]]; then
    info "Installing grub2-common so the GRUB configuration can be regenerated."
    install_packages grub2-common || warn "Could not install grub2-common."
  fi
}

run_grub() {
  printf '\n ▶ GRUB\n'
  printf '  ──────────────────────────────────────────────────────────────────────\n'
  if run_as_root sh -c 'command -v update-grub >/dev/null 2>&1'; then
    if run_as_root update-grub >>"$SETUP_LOG_FILE" 2>&1; then
      ok_indented 'GRUB Customizer package handled through the distro package path'
      ok_indented 'GRUB configuration updated'
    else
      warn 'Update-grub failed; the previous boot configuration was left in place.'
    fi
  elif run_as_root sh -c 'command -v grub-mkconfig >/dev/null 2>&1'; then
    if run_as_root grub-mkconfig -o /boot/grub/grub.cfg >>"$SETUP_LOG_FILE" 2>&1; then
      ok_indented 'GRUB Customizer package handled through the distro package path'
      ok_indented 'GRUB configuration updated'
    else
      warn 'grub-mkconfig failed; the previous boot configuration was left in place.'
    fi
  else
    warn 'No GRUB configuration generator is available.'
  fi
}
