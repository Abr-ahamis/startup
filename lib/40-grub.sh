#!/usr/bin/env bash
# Boot-critical GRUB theme deployment: discover, backup, stage, replace, verify.
if [[ -n "${__SETUP_GRUB_LOADED:-}" ]]; then return 0; fi
__SETUP_GRUB_LOADED=1

grub_theme_file_from() { sed -nE 's/^[[:space:]]*(export[[:space:]]+)?GRUB_THEME=["'\'' ]*([^"'\'' #]+).*$/\2/p' "$1" 2>/dev/null | head -n1; }
grub_find_theme_path() {
  local path='' generated='' candidate='' f=''
  [[ -r /etc/default/grub ]] && path="$(grub_theme_file_from /etc/default/grub)"
  # grub-mkconfig sources /etc/default/grub first, then every
  # /etc/default/grub.d/*.cfg in sorted glob order; later assignments win, so
  # apply drop-ins in sorted order and let the last one set the effective path.
  for f in /etc/default/grub.d/*.cfg; do
    [[ -e "$f" ]] || continue
    candidate="$(grub_theme_file_from "$f")"
    [[ -n "$candidate" ]] && path="$candidate"
  done
  [[ ! -r /boot/grub/grub.cfg ]] || generated="$(grep -Eo '/[^"[:space:]]+/theme\.txt' /boot/grub/grub.cfg 2>/dev/null | head -n1)"
  # The effective /etc/default configuration (including drop-ins) is what the
  # generator embeds on the next regeneration, so it is authoritative.  The
  # active grub.cfg reference is only a hint when no GRUB_THEME is configured.
  if [[ -n "$generated" && -z "$path" ]]; then
    _setup_log_write WARN "no GRUB_THEME in /etc/default; adopting active grub.cfg reference $generated"
    path="$generated"
  elif [[ -n "$generated" && "$path" != "$generated" ]]; then
    _setup_log_write WARN "GRUB_THEME effective value $path differs from current grub.cfg reference $generated; regeneration will apply $path"
  fi
  [[ -n "$path" ]] || path='/boot/grub/themes/grub/theme.txt'
  printf '%s\n' "$path"
}
grub_find_theme_dirs() {
  local theme_path theme_dir f
  theme_path="$(grub_find_theme_path)"
  theme_dir="$(dirname -- "$theme_path")"
  printf '%s\n' "$theme_dir"
  for f in /usr/share/grub/themes/*/theme.txt; do
    [[ -f "$f" ]] || continue
    [[ "$(dirname -- "$f")" == "$theme_dir" ]] || printf '%s\n' "$(dirname -- "$f")"
  done
}
grub_set_theme() {
  local defaults=/etc/default/grub theme="$1" temp
  [[ -e "$defaults" && ! -L "$defaults" ]] || run_as_root install -m 644 /dev/null "$defaults" || return 1
  temp="$(run_as_root mktemp /etc/default/.grub.startup.XXXXXX)" || return 1
  # The redirection must execute in the elevated process: a root-created
  # mktemp file is intentionally not writable by the invoking desktop user.
  run_as_root sh -c 'awk -v value="$1" '\''BEGIN {done=0} /^[[:space:]]*GRUB_THEME=/ {if (!done) print value; done=1; next} {print} END {if (!done) print value}'\'' "$2" > "$3"' sh "GRUB_THEME=\"$theme\"" "$defaults" "$temp" || { run_as_root rm -f -- "$temp"; return 1; }
  run_as_root chmod 644 "$temp" && run_as_root mv -f -- "$temp" "$defaults"
}
grub_verify_theme() {
  local theme="$1" dest; dest="$(dirname -- "$theme")"
  [[ -f "$theme" && ! -L "$theme" && -d "$dest" ]] || return 1
  grep -qxF "GRUB_THEME=\"$theme\"" /etc/default/grub 2>/dev/null || return 1
  diff -qr --no-dereference "$SCRIPT_DIR/grub" "$dest" >/dev/null 2>&1
}
grub_regenerate() {
  local before after=/boot/grub/grub.cfg
  before="$(stat -c '%Y:%s' "$after" 2>/dev/null || printf missing)"
  if command -v update-grub >/dev/null 2>&1; then run_package_command 'update-grub' run_as_root timeout --foreground 5m update-grub
  elif command -v grub-mkconfig >/dev/null 2>&1; then run_package_command 'grub-mkconfig' run_as_root timeout --foreground 5m grub-mkconfig -o "$after"
  else return 1; fi
  [[ -s "$after" ]] || return 1
  # A same-second identical size result is allowed: generators can produce
  # identical content. Successful generator exit plus a nonempty cfg is proof.
  _setup_log_write VERIFY "subject=grub.cfg result=OK before=$before after=$(stat -c '%Y:%s' "$after" 2>/dev/null || true)"
}
# Restore theme, defaults, and grub.cfg from the run's backups. Every step runs
# with elevated privileges: the backup directory is created root-only (0700) and
# an unprivileged existence check would silently skip every restore.
grub_rollback_theme() {
  local dest="$1" backup_name="${2:-grub-theme}" backups="$SETUP_BACKUP_DIR"
  run_as_root sh -c '
    dest=$1 backup_name=$2 backups=$3
    rm -rf --one-file-system "$dest"
    [ -e "$backups/$backup_name" ] && cp -a "$backups/$backup_name" "$dest"
    [ -e "$backups/grub.defaults.bak" ] && cp -a "$backups/grub.defaults.bak" /etc/default/grub
    [ -e "$backups/grub.cfg.bak" ] && cp -a "$backups/grub.cfg.bak" /boot/grub/grub.cfg
  ' sh "$dest" "$backup_name" "$backups"
}
grub_rollback_all_themes() {
  local index
  for index in "${!GRUB_THEME_DIRS[@]}"; do
    grub_rollback_theme "${GRUB_THEME_DIRS[$index]}" "grub-theme-$index"
  done
}
install_grub_theme() {
  local src="$SCRIPT_DIR/grub" theme dest backup defaults_backup stage theme_dir index
  local -a theme_dirs=()
  [[ -f "$src/theme.txt" && -f "$src/grub-16x9.png" ]] || { required_failure "GRUB theme assets are incomplete: $src"; return 1; }
  [[ -d /boot/grub ]] || { required_failure '/boot/grub is unavailable; cannot safely install GRUB theme'; return 1; }
  theme="$(grub_find_theme_path)"; dest="$(dirname -- "$theme")"; backup="$SETUP_BACKUP_DIR/grub-theme"; defaults_backup="$SETUP_BACKUP_DIR/grub.defaults.bak"
  mapfile -t theme_dirs < <(grub_find_theme_dirs)
  GRUB_THEME_DIRS=("${theme_dirs[@]}")
  run_as_root install -d -m 700 "$SETUP_BACKUP_DIR" || return 1
  [[ ! -e /etc/default/grub || -L /etc/default/grub ]] || run_as_root cp -a /etc/default/grub "$defaults_backup" || return 1
  [[ ! -e /boot/grub/grub.cfg || -L /boot/grub/grub.cfg ]] || run_as_root cp -a /boot/grub/grub.cfg "$SETUP_BACKUP_DIR/grub.cfg.bak" || return 1
  for index in "${!theme_dirs[@]}"; do
    theme_dir="${theme_dirs[$index]}"
    backup="$SETUP_BACKUP_DIR/grub-theme-$index"
    if [[ -e "$theme_dir" || -L "$theme_dir" ]]; then
      [[ ! -L "$theme_dir" ]] || { required_failure "Refusing symlinked GRUB theme destination: $theme_dir"; return 1; }
      run_as_root cp -a "$theme_dir" "$backup" || return 1
    fi
    stage="$(run_as_root mktemp -d "$(dirname -- "$theme_dir")/.startup-grub.XXXXXX")" || return 1
    if ! run_as_root cp -a "$src/." "$stage/" || ! diff -qr --no-dereference "$src" "$stage" >/dev/null; then
      run_as_root rm -rf -- "$stage"
      required_failure 'GRUB staging verification failed'
      return 1
    fi
    if ! run_as_root rm -rf --one-file-system "$theme_dir" || ! run_as_root mv -- "$stage" "$theme_dir" ||
      ! run_as_root find "$theme_dir" -type d -exec chmod 755 {} + || ! run_as_root find "$theme_dir" -type f -exec chmod 644 {} +; then
      grub_rollback_all_themes
      required_failure "GRUB theme deployment failed; previous files were restored when available"
      return 1
    fi
  done
  if ! grub_set_theme "$theme" || ! grub_verify_theme "$theme"; then
    grub_rollback_all_themes
    required_failure "GRUB theme deployment failed; previous files were restored when available"
    return 1
  fi
  GRUB_THEME_PATH="$theme"; _setup_log_write VERIFY "subject=GRUB-theme result=OK source=$src destination=$dest"
}
run_grub() {
  printf '\n ▶ GRUB\n'
  if [[ ! -d /boot/grub ]]; then
    info 'GRUB is not installed or active on this system; skipping GRUB theme installation.'
    _setup_log_write INFO 'GRUB stage skipped: /boot/grub is unavailable.'
    return 0
  fi
  install_grub_theme || return 1
  if ! grub_regenerate; then
    grub_rollback_all_themes
    required_failure 'GRUB regeneration failed; previous theme, defaults, and grub.cfg were restored when available'; return 1
  fi
  # /boot/grub/grub.cfg is root-only (0600) on Debian/Kali, so it must be read
  # with elevated privileges. The generator emits the theme path literally or
  # prefixed with ($root), possibly quoted; verify with a substring match and
  # log the actual embedded line for future diagnosis.
  local theme_line
  theme_line="$(run_as_root sh -c 'grep -E "set theme=" "$1" 2>/dev/null | tail -n1' sh /boot/grub/grub.cfg)" || true
  if [[ "$theme_line" != *"$GRUB_THEME_PATH"* ]]; then
    _setup_log_write WARN "expected GRUB_THEME_PATH=$GRUB_THEME_PATH; embedded theme line: ${theme_line:-<none>}"
    grub_rollback_theme "$(dirname -- "$GRUB_THEME_PATH")"
    required_failure 'GRUB verification failed; expected theme reference was not found in grub.cfg; previous theme, defaults, and grub.cfg were restored when available'; return 1
  fi
  _setup_log_write VERIFY "subject=grub-theme-embedding result=OK line=$theme_line"
  ok_indented "GRUB theme installed and grub.cfg verified: $GRUB_THEME_PATH"
}
