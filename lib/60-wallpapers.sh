#!/usr/bin/env bash
# Wallpaper discovery and replacement.
# System wallpaper files are backed up before replacement and validated after
# writing. Files are replaced directly for speed; desktop filenames and paths
# remain unchanged so existing wallpaper references continue to work.

if [[ -n "${__SETUP_WALLPAPERS_LOADED:-}" ]]; then return 0; fi
__SETUP_WALLPAPERS_LOADED=1

declare -a bg_labels=() bg_paths=() bg_real_paths=() replaced=() skipped=()
declare -A seen_real=()

is_image_file() {
  local path="${1:-}" real mime
  real="$(readlink -f -- "$path" 2>/dev/null || true)"
  [[ -f "$real" ]] || return 1
  if ! command -v file >/dev/null 2>&1; then
    warn "The file command is unavailable; cannot identify wallpaper images."
    return 1
  fi
  mime="$(file -b --mime-type -- "$real" 2>/dev/null || true)"
  [[ "$mime" == image/* ]]
}

choose_source_image() {
  local index="${1:-0}"
  local -a sources=("$SCRIPT_DIR/wallpaper/IMG1.jpg" "$SCRIPT_DIR/wallpaper/IMG2.jpg")
  printf '%s\n' "${sources[$((index % ${#sources[@]}))]}"
}

install_user_wallpapers() {
  local target="$TARGET_HOME/.local/share/backgrounds/startup" source
  run_as_root install -d -m 755 "$target" || return 1
  for source in "$SCRIPT_DIR/wallpaper/IMG1.jpg" "$SCRIPT_DIR/wallpaper/IMG2.jpg"; do
    [[ -f "$source" ]] || continue
    run_as_root install -m 644 "$source" "$target/$(basename -- "$source")" || return 1
  done
  run_as_root chown -R "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.local/share/backgrounds" || return 1
  ok "User wallpapers installed"
}

discover_background_images() {
  local root="${STARTUP_BACKGROUND_ROOT:-/usr/share/backgrounds}" entry real label manifest
  [[ -d "$root" ]] || return 1
  manifest="$SETUP_RUNTIME_DIR/wallpapers.$$"
  find -L "$root" -mindepth 1 -type f -print0 2>/dev/null | sort -z >"$manifest" || { rm -f -- "$manifest"; return 1; }
  while IFS= read -r -d '' entry; do
    real="$(readlink -f -- "$entry" 2>/dev/null || true)"
    [[ -f "$real" ]] || continue
    is_image_file "$entry" || continue
    [[ -n "${seen_real[$real]:-}" ]] && continue
    seen_real["$real"]=1
    label="${entry#"$root"/}"
    bg_labels+=("$label")
    bg_paths+=("$entry")
    bg_real_paths+=("$real")
  done <"$manifest"
  rm -f -- "$manifest"
}

backup_wallpaper() {
  local source="${1:-}" backup_root="${2:-}" background_root="${3:-/usr/share/backgrounds}" real relative
  real="$(readlink -f -- "$source" 2>/dev/null || true)"
  [[ -f "$real" ]] || return 1
  relative="${real#"$background_root"/}"
  [[ "$relative" == "$real" ]] && relative="$(basename -- "$real")"
  run_as_root install -d -m 700 "$backup_root/$(dirname -- "$relative")" || return 1
  run_as_root cp -a -- "$real" "$backup_root/$relative"
}

replace_wallpaper() {
  local source="${1:-}" target="${2:-}" backup_root="${3:-}" background_root="${4:-/usr/share/backgrounds}" temp
  [[ -f "$source" && -f "$target" ]] || return 1
  backup_wallpaper "$target" "$backup_root" "$background_root" || return 1
  temp="$(run_as_root mktemp "$(dirname -- "$target")/.startup-wallpaper.XXXXXX")" || return 1
  run_as_root install -m 644 "$source" "$temp" || { run_as_root rm -f -- "$temp"; return 1; }
  run_as_root chmod 644 -- "$temp" || true
  if ! is_image_file "$temp"; then
    run_as_root rm -f -- "$temp"
    return 1
  fi
  if ! run_as_root mv -f -- "$temp" "$target"; then
    run_as_root rm -f -- "$temp"
    return 1
  fi
  run_as_root chmod 644 -- "$target"
}

run_wallpapers() {
  printf '\n──────────────────────────────────────────────────────────────────────\n'
  printf ' ▶  Wallpapers\n'
  printf '────────────────────────────────────────────────────────────\n'
  require_dir "$SCRIPT_DIR/wallpaper" "wallpaper folder"
  require_file "$SCRIPT_DIR/wallpaper/IMG1.jpg" "wallpaper/IMG1.jpg"
  require_file "$SCRIPT_DIR/wallpaper/IMG2.jpg" "wallpaper/IMG2.jpg"
  install_user_wallpapers || { warn "Managed user wallpapers could not be installed."; return 1; }

  local root="${STARTUP_BACKGROUND_ROOT:-/usr/share/backgrounds}"
  local backup_dir="$SETUP_BASE_DIR/wallpaper-backups/$SETUP_TIMESTAMP"
  SETUP_WALLPAPER_BACKUP_DIR="$backup_dir"
  local i source source_name target label

  discover_background_images || { warn "Wallpaper directory is unavailable: $root"; return 0; }

  for i in "${!bg_paths[@]}"; do
    target="${bg_real_paths[$i]}"
    label="${bg_labels[$i]}"
    source="$(choose_source_image "$i")"
    source_name="$(basename -- "$source")"
    if replace_wallpaper "$source" "$target" "$backup_dir" "$root"; then
      replaced+=("$label")
      printf '  %s[ OK ]%s %-24s -> %s\n' "$SETUP_COLOR_OK" "$SETUP_COLOR_RST" "$source_name" "$label"
    else
      skipped+=("$label")
      printf '  %s[WARN]%s %-24s -> %s\n' "$SETUP_COLOR_WARN" "$SETUP_COLOR_RST" "$source_name" "$label"
      _setup_log_write WARN "Wallpaper replacement failed: $label"
    fi
  done

  printf '────────────────────────────────────────────────────────────\n'
  ok "Wallpaper scan and replacement complete: ${#replaced[@]} replaced"
  printf '────────────────────────────────────────────────────────────\n'
  if (( ${#skipped[@]} )); then
    warn "Wallpaper files skipped: ${#skipped[@]}; backups are in $backup_dir"
  fi
}
