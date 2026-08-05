#!/usr/bin/env bash
# Distribution detection.  Add a new family here and its package map in 20-packages.sh.

if [[ -n "${__SETUP_DISTRO_LOADED:-}" ]]; then return 0; fi
__SETUP_DISTRO_LOADED=1

detect_distro() {
  DISTRO_ID=unknown DISTRO_NAME=Unknown DISTRO_PRETTY=Unknown DISTRO_FAMILY=unknown PKG_MANAGER=unknown
  if [[ ! -r /etc/os-release ]]; then
    error "Cannot read /etc/os-release; this installer supports Linux distributions only."
    return 1
  fi
  # shellcheck disable=SC1091
  source /etc/os-release
  DISTRO_ID="${ID:-unknown}"
  DISTRO_ID="${DISTRO_ID,,}"
  DISTRO_NAME="${NAME:-$DISTRO_ID}"
  DISTRO_PRETTY="${PRETTY_NAME:-$DISTRO_NAME}"
  local ids=" $DISTRO_ID ${ID_LIKE:-} "
  if [[ "$ids" == *" debian "* ]] || [[ "$DISTRO_ID" =~ ^(debian|ubuntu|linuxmint|kali)$ ]]; then
    DISTRO_FAMILY=debian; PKG_MANAGER=apt
  elif [[ "$ids" == *" arch "* ]] || [[ "$DISTRO_ID" == arch ]]; then
    DISTRO_FAMILY=arch; PKG_MANAGER=pacman
  else
    error "Unsupported distribution: $DISTRO_PRETTY. Supported: Debian, Ubuntu, Linux Mint, Kali Linux, and Arch Linux."
    return 1
  fi
  if ! command -v "$PKG_MANAGER" >/dev/null 2>&1 && ! { [[ "$PKG_MANAGER" == apt ]] && command -v apt-get >/dev/null 2>&1; }; then
    error "Expected package manager '$PKG_MANAGER' is unavailable."
    return 1
  fi
}

run_distro() {
  detect_distro || exit 1
  section_setup "System information"
  printf 'Distribution : %s\nID           : %s\nFamily       : %s\nPackage mgr  : %s\nUser         : %s\nHome         : %s\n' \
    "$DISTRO_PRETTY" "$DISTRO_ID" "$DISTRO_FAMILY" "$PKG_MANAGER" "$TARGET_USER" "$TARGET_HOME"
  if [[ "$DISTRO_ID" == kali ]]; then
    run_as_root install -o "$TARGET_USER" -g "$TARGET_GROUP" -m 644 /dev/null "$TARGET_HOME/.hushlogin" || warn "Could not suppress Kali's login message"
  fi
}
