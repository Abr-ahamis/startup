#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [ -z "$TARGET_HOME" ]; then
  TARGET_HOME="$HOME"
fi
BACKUP_DIR="$TARGET_HOME/.config/sway-bar-backup-$STAMP"

log() { printf "[sway-bar] %s\n" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
as_user() {
  if [ "$(id -u)" -eq 0 ] && [ "$TARGET_USER" != "root" ]; then
    sudo -u "$TARGET_USER" "$@"
  else
    "$@"
  fi
}
as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

detect_distro() {
  . /etc/os-release
  case "${ID:-} ${ID_LIKE:-}" in
    *arch*|*manjaro*) printf arch ;;
    *debian*|*ubuntu*) printf debian ;;
    *) printf unknown ;;
  esac
}

install_packages() {
  distro="$(detect_distro)"
  case "$distro" in
    arch)
      pkgs=(sway i3blocks rofi-wayland networkmanager bluez blueman pipewire wireplumber playerctl brightnessctl wl-clipboard xclip ttf-font-awesome pavucontrol dunst)
      missing=()
      for pkg in "${pkgs[@]}"; do pacman -Qi "$pkg" >/dev/null 2>&1 || missing+=("$pkg"); done
      if [ "${#missing[@]}" -gt 0 ]; then as_root pacman -S --needed "${missing[@]}"; fi
      ;;
    debian)
      pkgs=(sway i3blocks rofi network-manager bluez blueman pipewire wireplumber playerctl brightnessctl wl-clipboard xclip fonts-font-awesome pavucontrol dunst)
      optional_pkgs=()
      as_root apt-get update
      as_root apt-get install -y "${pkgs[@]}"
      for pkg in "${optional_pkgs[@]}"; do
        if apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {exit ($2 == "(none)")}' ; then
          as_root apt-get install -y "$pkg"
        else
          log "Optional package unavailable on this distro: $pkg"
        fi
      done
      ;;
    *)
      log "Unsupported distro for automatic package install; install dependencies manually."
      ;;
  esac
}

install_greenclip() {
  if have greenclip; then return 0; fi
  distro="$(detect_distro)"
  if [ "$distro" = arch ] && as_user command -v yay >/dev/null 2>&1; then
    as_user yay -S --needed greenclip
    return 0
  fi
  log "greenclip is not installed. Install it from your distro/AUR or upstream release."
}

ensure_font() {
  as_user fc-cache -f >/dev/null 2>&1 || true
  if as_user fc-list | grep -qi "awesome"; then return 0; fi
  log "Font Awesome was not detected. Install ttf-font-awesome/fonts-font-awesome before relying on icons."
}

backup_path() {
  src="$1"
  if [ -e "$src" ] || [ -L "$src" ]; then
    mkdir -p "$BACKUP_DIR"
    cp -a "$src" "$BACKUP_DIR/"
    log "Backed up $src to $BACKUP_DIR"
  fi
}

patch_sway_config() {
  target="$TARGET_HOME/.config/sway/config"
  mkdir -p "$(dirname "$target")"
  if [ ! -f "$target" ]; then
    cp "$ROOT/sway/config" "$target"
    return 0
  fi

  tmp="$(mktemp)"
  awk '
    /^[[:space:]]*bar[[:space:]]*\{/ {skip=1; depth=1; next}
    skip {
      depth += gsub(/\{/, "{")
      depth -= gsub(/\}/, "}")
      if (depth <= 0) skip=0
      next
    }
    {print}
  ' "$target" > "$tmp"

  {
    cat "$tmp"
    printf "\n"
    awk '
      /^[[:space:]]*bar[[:space:]]*\{/ {copy=1; depth=0}
      copy {
        print
        depth += gsub(/\{/, "{")
        depth -= gsub(/\}/, "}")
        if (depth <= 0) exit
      }
    ' "$ROOT/sway/config"
    grep -q "greenclip daemon" "$tmp" || printf "\nexec_always --no-startup-id greenclip daemon\n"
    grep -q "exec --no-startup-id dunst" "$tmp" || printf "exec --no-startup-id dunst\n"
  } > "$target"
  rm -f "$tmp"
}

deploy() {
  backup_path "$TARGET_HOME/.config/sway/config"
  backup_path "$TARGET_HOME/.config/i3blocks/config"
  backup_path "$TARGET_HOME/.config/sway/scripts"

  mkdir -p "$TARGET_HOME/.config/sway/scripts" "$TARGET_HOME/.config/i3blocks" "$TARGET_HOME/.config/rofi/themes"
  cp "$ROOT/scripts/"*.sh "$TARGET_HOME/.config/sway/scripts/"
  chmod +x "$TARGET_HOME/.config/sway/scripts/"*.sh
  cp "$ROOT/i3blocks/config" "$TARGET_HOME/.config/i3blocks/config"
  cp "$ROOT/rofi/themes/dark.rasi" "$TARGET_HOME/.config/rofi/themes/dark.rasi"
  patch_sway_config
  chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/sway" "$TARGET_HOME/.config/i3blocks" "$TARGET_HOME/.config/rofi" "$BACKUP_DIR" 2>/dev/null || true
}

reload_sway() {
  if have swaymsg && [ -n "${SWAYSOCK:-}" ]; then
    swaymsg reload >/dev/null || true
  else
    log "Sway reload skipped; no active SWAYSOCK detected."
  fi
}

main() {
  log "Installing required packages when supported."
  install_packages
  install_greenclip
  ensure_font
  deploy
  reload_sway
  log "Target user: $TARGET_USER"
  log "Deployed i3blocks config: $TARGET_HOME/.config/i3blocks/config"
  log "Deployed sway scripts: $TARGET_HOME/.config/sway/scripts"
  log "Patched sway config: $TARGET_HOME/.config/sway/config"
  log "Backups, if needed: $BACKUP_DIR"
  log "Done. Reload Sway or run 'swaymsg reload' if it was not active."
}

main "$@"
