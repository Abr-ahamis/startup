#!/usr/bin/env bash
# Distribution detection.  Add a new family here and its package map in 20-packages.sh.

if [[ -n "${__SETUP_DISTRO_LOADED:-}" ]]; then return 0; fi
__SETUP_DISTRO_LOADED=1

detect_distro() {
  DISTRO_ID=unknown DISTRO_NAME=Unknown DISTRO_PRETTY=Unknown DISTRO_FAMILY=unknown PKG_MANAGER=unknown
  local os_release="${NEO_OS_RELEASE_FILE:-/etc/os-release}"
  if [[ ! -r "$os_release" ]]; then
    error "Cannot read /etc/os-release; this installer supports Linux distributions only."
    return 1
  fi
  # shellcheck disable=SC1091
  source "$os_release"
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
  printf '\n%s╔══════════════════════════════════════════════════════════════════════╗%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  printf '%s║%s%s                             NEO STARTUP                              %s%s║%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST" "$SETUP_COLOR_BOLD" "$SETUP_COLOR_RST" "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  printf '%s║%s                         Installation Report                          %s%s║%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST" "$SETUP_COLOR_DIM" "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  printf '%s╚══════════════════════════════════════════════════════════════════════╝%s\n\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  printf '  %s%s▶  System%s\n' "$SETUP_COLOR_BOLD" "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  printf '  %s──────────────────────────────────────────────────────────────────────%s\n' "$SETUP_COLOR_CYAN" "$SETUP_COLOR_RST"
  printf '  Distribution           %s\n' "$DISTRO_PRETTY"
  printf '  Package manager        %s\n' "$PKG_MANAGER"
  printf '  Current environment    %s\n' "${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-TTY}}"
  printf '  Target user            %s\n' "$TARGET_USER"
  printf '  Installation mode      Existing OS → Add Sway\n'
  printf '  OS upgrade    ----->      not requested\n'
  printf '  GNOME/other desktop removal ---->   existing desktop preserved\n\n'
  if [[ "$DISTRO_ID" == kali ]]; then
    # This is a target-user preference, not a system operation; do not force
    # a sudo prompt before package discovery has even started.
    run_as_target install -m 644 /dev/null "$TARGET_HOME/.hushlogin" || warn "Could not suppress Kali's login message"
  fi
}
