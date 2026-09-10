#!/usr/bin/env bash
# Debian/Kali GTK theme installation and activation for adw-gtk3.
# The main installer continues past optional theme failures; do not enable
# errexit globally when this module is sourced.
set -uo pipefail

if [[ -n "${__SETUP_THEME_LOADED:-}" ]]; then
  return 0
fi
__SETUP_THEME_LOADED=1

run_theme() {
  section_setup "GTK theme"

  case "${DISTRO_ID:-}" in
    debian|kali) ;;
    *)
      info "adw-gtk3 is only managed on Debian and Kali; skipped for ${DISTRO_PRETTY:-this system}."
      return 0
      ;;
  esac

  local theme_name="adw-gtk3"
  local theme_dark_name="adw-gtk3-dark"
  local install_dir="$TARGET_HOME/.local/share/themes"
  local user_theme_dir="$install_dir/$theme_name"
  local system_theme_dir="/usr/share/themes/$theme_name"
  local installed=0
  local tmpdir="" api_json="" asset_url="" asset_name=""

  mkdir -p "$install_dir"

  if [[ -d "$user_theme_dir" || -d "$system_theme_dir" || -d "/usr/share/themes/$theme_dark_name" ]]; then
    installed=1
  fi

  if (( installed == 0 )); then
    case "${DISTRO_ID:-}" in
      kali)
        if package_available adw-gtk3-kali; then
          if install_packages adw-gtk3-kali; then
            installed=1
          fi
        fi
        ;;
      debian)
        if package_available adw-gtk3; then
          if install_packages adw-gtk3; then
            installed=1
          fi
        fi
        ;;
    esac
  fi

  if (( installed == 0 )); then
    tmpdir="$(mktemp -d)"
    trap 'rm -rf -- "$tmpdir"' RETURN

    if ! command -v curl >/dev/null 2>&1; then
      install_packages curl
    fi
    if ! command -v jq >/dev/null 2>&1; then
      install_packages jq
    fi

    api_json="$tmpdir/release.json"
    if ! run_logged "Fetching latest adw-gtk3 release info" \
      curl -fsSL "https://api.github.com/repos/lassekongo83/adw-gtk3/releases/latest" -o "$api_json"; then
      warn "Could not fetch the latest adw-gtk3 release information."
      return 1
    fi

    asset_url="$({
      jq -r '
        .assets[]
        | select(.name | endswith(".tar.xz"))
        | .browser_download_url
      ' "$api_json" | head -n1
    })"

    asset_name="$({
      jq -r '
        .assets[]
        | select(.name | endswith(".tar.xz"))
        | .name
      ' "$api_json" | head -n1
    })"

    if [[ -z "$asset_url" || -z "$asset_name" || "$asset_url" == "null" ]]; then
      warn "Could not find a .tar.xz release asset for adw-gtk3."
      return 1
    fi

    if ! run_logged "Downloading adw-gtk3 release tarball" \
      curl -fL --retry 3 --retry-delay 1 -o "$tmpdir/$asset_name" "$asset_url"; then
      warn "Download failed for adw-gtk3 release tarball."
      return 1
    fi

    if ! run_logged "Extracting adw-gtk3" \
      tar -xJf "$tmpdir/$asset_name" -C "$install_dir"; then
      warn "Could not extract adw-gtk3 tarball."
      return 1
    fi

    installed=1
  fi

  if (( installed == 1 )); then
    run_as_root chown -R "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.local/share/themes" 2>/dev/null || true
    ok "adw-gtk3 installed"
  else
    warn "adw-gtk3 could not be installed from a package or from the official source repository."
    return 1
  fi
}
