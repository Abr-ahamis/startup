#!/usr/bin/env bash
# Credential integration: install, configure, verify.  Edits are idempotent and
# backed up before PAM is changed.

if [[ -n "${__SETUP_SECURITY_LOADED:-}" ]]; then return 0; fi
__SETUP_SECURITY_LOADED=1

security_backup_dir="$SETUP_BASE_DIR/security-backups/$SETUP_TIMESTAMP"

security_write_browser_flag() {
  local file="${1:-}" flag='--password-store=gnome-libsecret'
  [[ -n "$file" ]] || return 1
  run_as_target mkdir -p "$(dirname "$file")" || return 1
  if [[ -f "$file" ]] && grep -qxF -- "$flag" "$file"; then return 0; fi
  [[ -f "$file" ]] && run_as_target cp -a "$file" "$file.bak.$SETUP_TIMESTAMP"
  printf '%s\n' "$flag" | run_as_target tee -a "$file" >/dev/null
}

security_find_git_helper() {
  local candidate
  for candidate in /usr/local/libexec/git-core/git-credential-libsecret /usr/lib/git-core/git-credential-libsecret /usr/libexec/git-core/git-credential-libsecret; do
    [[ -x "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

security_build_git_helper() {
  local source_dir="/usr/share/doc/git/contrib/credential/libsecret"
  install_feature git_libsecret
  [[ -f "$source_dir/Makefile" ]] || return 1
  info "Building Git libsecret helper (maximum 30 seconds)..."
  run_logged "Building Git libsecret helper" run_as_root timeout --foreground 30s make -C "$source_dir" || return 1
  [[ -x "$source_dir/git-credential-libsecret" ]] || return 1
  run_as_root install -D -m 755 "$source_dir/git-credential-libsecret" /usr/local/libexec/git-core/git-credential-libsecret
}

security_configure_git_libsecret() {
  command -v git >/dev/null 2>&1 || { warn "Git is unavailable; cannot configure its credential helper."; return 1; }
  local helper="$(security_find_git_helper || true)"
  if [[ -z "$helper" ]]; then security_build_git_helper || { warn "Could not build Git libsecret helper."; return 1; }; helper="$(security_find_git_helper || true)"; fi
  [[ -n "$helper" ]] || { warn "Git libsecret helper is unavailable after repair."; return 1; }
  run_as_target git config --global credential.helper "$helper" || return 1
  [[ "$(run_as_target git config --global --get credential.helper 2>/dev/null || true)" == "$helper" ]]
}

security_configure_pam_keyring() {
  local pam_file="/etc/pam.d/login" module="" line
  install_feature keyring_pam
  for module in /usr/lib/*/security/pam_gnome_keyring.so /usr/lib/security/pam_gnome_keyring.so; do [[ -f "$module" ]] && break; module=""; done
  [[ -n "$module" ]] || { warn "pam_gnome_keyring.so is unavailable; PAM keyring integration cannot be configured."; return 1; }
  [[ -f "$pam_file" ]] || { warn "$pam_file is unavailable; PAM keyring integration cannot be configured."; return 1; }
  run_as_root install -d -m 700 "$security_backup_dir"
  run_as_root cp -a "$pam_file" "$security_backup_dir/login.bak" || return 1
  for line in 'auth optional pam_gnome_keyring.so' 'session optional pam_gnome_keyring.so auto_start'; do
    run_as_root grep -qxF -- "$line" "$pam_file" || printf '%s\n' "$line" | run_as_root tee -a "$pam_file" >/dev/null
  done
  run_as_root grep -qxF -- 'auth optional pam_gnome_keyring.so' "$pam_file" && run_as_root grep -qxF -- 'session optional pam_gnome_keyring.so auto_start' "$pam_file"
}

security_keyring_runtime_check() {
  local runtime keyring_dir owner
  runtime="$(target_runtime_dir)"
  keyring_dir="${GNOME_KEYRING_CONTROL:-$runtime/keyring}"
  target_session_available || { info "GNOME Keyring runtime checks deferred until the target user session is active."; return 0; }
  if run_as_target pgrep -f '^/usr/bin/gnome-keyring-daemon([[:space:]]|$)' >/dev/null 2>&1; then ok 'GNOME Keyring daemon running'; else warn 'GNOME Keyring daemon is not running'; fi
  if run_as_target_session timeout --foreground 5s busctl --user status org.freedesktop.secrets >/dev/null 2>&1; then
    ok 'GNOME Secret Service available'
    owner="$(run_as_target_session timeout --foreground 5s busctl --user status org.freedesktop.secrets 2>/dev/null | awk -F= '/^PID=/{print $2; exit}' || true)"
    [[ "$owner" =~ ^[0-9]+$ ]] && ok 'GNOME Secret Service owner detected' || warn 'GNOME Secret Service owner unavailable'
  else
    warn 'GNOME Secret Service unavailable on the target user D-Bus'
  fi
  [[ -S "$keyring_dir/control" ]] && ok 'GNOME Keyring control socket available' || warn 'GNOME Keyring control socket unavailable'
  [[ -S "$keyring_dir/ssh" ]] && ok 'GNOME Keyring SSH socket available' || info 'GNOME Keyring SSH socket unavailable; SSH integration is deferred.'
}

security_configure_vscode() {
  local argv="$TARGET_HOME/.config/Code/User/argv.json"
  command -v code >/dev/null 2>&1 || { info 'VS Code not installed; GNOME Keyring integration prepared.'; return 0; }
  run_as_root install -d -m 700 "$(dirname "$argv")" || return 1
  run_as_target env TARGET_ARGV="$argv" python3 -c 'import json,os,pathlib,tempfile; p=pathlib.Path(os.environ["TARGET_ARGV"]); d=json.loads(p.read_text()) if p.exists() else {}; assert isinstance(d,dict); d["password-store"]="gnome-libsecret"; p.parent.mkdir(parents=True,exist_ok=True); fd,t=tempfile.mkstemp(prefix=".argv.",dir=p.parent); f=os.fdopen(fd,"w"); json.dump(d,f,indent=2); f.write(chr(10)); f.close(); os.replace(t,p)' >>"$SETUP_LOG_FILE" 2>&1 || return 1
  run_as_root chown "$TARGET_USER:$TARGET_GROUP" "$argv" && run_as_root chmod 600 "$argv" || return 1
  ok 'VS Code gnome-libsecret integration configured'
}

run_security() {
  setup_double_sep
  printf '%sSECURITY LAYER : Credential + System Protection%s\n' "$SETUP_COLOR_BOLD" "$SETUP_COLOR_RST"
  setup_double_sep
  section_setup 'Secret Storage Verification'
  install_feature secret
  if command -v gnome-keyring-daemon >/dev/null 2>&1; then ok "GNOME Keyring                installed"; else warn "GNOME Keyring is unavailable"; fi
  if command -v secret-tool >/dev/null 2>&1; then ok "Libsecret Tools              installed"; else warn "Libsecret tools are unavailable"; fi
  setup_sep
  security_keyring_runtime_check
  setup_sep
  command -v seahorse >/dev/null 2>&1 && ok "Seahorse                     installed"
  command -v gpg >/dev/null 2>&1 && ok "GnuPG                        installed"
  command -v age >/dev/null 2>&1 && ok "Age encryption                installed"
  command -v aa-status >/dev/null 2>&1 && ok "AppArmor                     installed"
  command -v bwrap >/dev/null 2>&1 && ok "Bubblewrap                   installed"
  command -v cryptsetup >/dev/null 2>&1 && ok "Cryptsetup                   installed"
  section_setup 'Browser Credential Protection'
  local browser flags
  for browser in chromium google-chrome brave-browser; do
    command -v "$browser" >/dev/null 2>&1 || continue
    case "$browser" in chromium) flags="$TARGET_HOME/.config/chromium-flags.conf";; google-chrome) flags="$TARGET_HOME/.config/chrome-flags.conf";; brave-browser) flags="$TARGET_HOME/.config/brave-flags.conf";; esac
    security_write_browser_flag "$flags" && ok "$browser detected — using GNOME Secret Service" || warn "Could not configure $browser credential storage."
  done
  section_setup 'Application Credential Protection'
  security_configure_vscode || warn "VS Code keyring integration could not be configured."
  security_configure_git_libsecret && ok "Git libsecret credential helper configured and verified" || warn "Git libsecret repair could not be completed."
  security_configure_pam_keyring && ok "PAM gnome-keyring unlock configured" || warn "PAM GNOME Keyring integration could not be completed."
}
