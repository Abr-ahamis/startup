#!/usr/bin/env bash
# Shared helper for optional installers. It intentionally has no side effects when sourced.
set -u

optional_cleanup() {
  [[ -n "${OPTIONAL_TMPDIR:-}" && -d "${OPTIONAL_TMPDIR:-}" ]] && rm -rf -- "$OPTIONAL_TMPDIR"
}
optional_interrupted() {
  printf '\nInterrupted; cleaning up temporary files.\n' >&2
  optional_cleanup
  exit 130
}
trap optional_interrupted INT TERM
trap optional_cleanup EXIT

optional_detect() {
  [[ -r /etc/os-release ]] || { echo 'Unsupported system: /etc/os-release is unavailable.' >&2; return 1; }
  # shellcheck disable=SC1091
  source /etc/os-release
  OPTIONAL_ID="${ID:-unknown}"; OPTIONAL_ID="${OPTIONAL_ID,,}"; OPTIONAL_LIKE=" ${ID_LIKE:-} "
  if [[ "$OPTIONAL_ID" =~ ^(debian|ubuntu|linuxmint|kali)$ ]] || [[ "$OPTIONAL_LIKE" == *' debian '* ]]; then OPTIONAL_PM=apt
  elif [[ "$OPTIONAL_ID" == arch ]] || [[ "$OPTIONAL_LIKE" == *' arch '* ]]; then OPTIONAL_PM=pacman
  else echo "Unsupported distribution: ${PRETTY_NAME:-$OPTIONAL_ID}" >&2; return 1; fi
}
as_root() {
  if (( EUID == 0 )); then
    "$@"
    return $?
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    echo 'This installer requires root or sudo privileges.' >&2
    return 127
  fi
  sudo "$@"
}
run_as_target() {
  if [[ "$(id -un)" == "$target_user" ]]; then "$@"; elif (( EUID == 0 )); then runuser -u "$target_user" -- "$@"; else sudo -u "$target_user" -H "$@"; fi
}
optional_refresh() { case "$OPTIONAL_PM" in apt) as_root timeout --foreground 10m apt-get update;; pacman) as_root timeout --foreground 10m pacman -Sy --noconfirm;; esac; }
optional_install() { case "$OPTIONAL_PM" in apt) as_root timeout --foreground 20m apt-get install -y --no-install-recommends "$@";; pacman) as_root timeout --foreground 20m pacman -S --needed --noconfirm "$@";; esac; }

require_download_tool() {
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || {
    echo 'curl or wget is required for this installer.' >&2
    return 1
  }
}

download_file() {
  local url="${1:-}" destination="${2:-}"
  [[ -n "$url" && -n "$destination" ]] || return 1
  require_download_tool || return 1
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 4 --retry-delay 2 --connect-timeout 20 --max-time 300 --output "$destination" "$url"
  else
    wget --https-only --tries=4 --timeout=20 --output-document="$destination" "$url"
  fi
}

github_latest_asset_url() {
  local repository="${1:-}" asset_name="${2:-}" api_url json
  [[ -n "$repository" && -n "$asset_name" ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  api_url="https://api.github.com/repos/$repository/releases/latest"
  if command -v curl >/dev/null 2>&1; then
    json="$(curl -fsSL --retry 4 --retry-delay 2 --connect-timeout 20 --max-time 120 -H 'Accept: application/vnd.github+json' "$api_url")" || return 1
  elif command -v wget >/dev/null 2>&1; then
    json="$(wget --https-only --tries=4 --timeout=20 -qO- "$api_url")" || return 1
  else
    return 1
  fi
  jq -er --arg name "$asset_name" '.assets[] | select(.name == $name) | .browser_download_url' <<<"$json"
}
target_user="${STARTUP_TARGET_USER:-${SUDO_USER:-${USER:-$(id -un)}}}"
target_home="${STARTUP_TARGET_HOME:-$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)}"
target_home="${target_home:-${HOME:-/root}}"
