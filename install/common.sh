#!/usr/bin/env bash
# Shared helper for optional installers. It intentionally has no side effects when sourced.
set -u

optional_cleanup() {
  [[ -n "${OPTIONAL_TMPDIR:-}" && -d "${OPTIONAL_TMPDIR:-}" ]] && rm -rf -- "$OPTIONAL_TMPDIR"
}
optional_interrupted() {
  printf '\n[%s] Installation interrupted. No further changes were made.\n' "$(date +%H:%M:%S)" >&2
  optional_cleanup
  exit 130
}
trap optional_interrupted INT TERM HUP
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
optional_apt_lock_holder() {
  local lock pid
  command -v fuser >/dev/null 2>&1 || return 1
  for lock in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock; do
    [[ -e "$lock" ]] || continue
    pid="$(fuser "$lock" 2>/dev/null | awk 'NR==1 {print $1}' | tr -cd '0-9')"
    [[ -n "$pid" ]] && { printf '%s\n' "$pid"; return 0; }
  done
}
optional_wait_for_apt() {
  [[ "${OPTIONAL_PM:-}" == apt ]] || return 0
  local holder deadline=$(( $(date +%s) + ${STARTUP_APT_LOCK_TIMEOUT:-300} )) announced=0
  while holder="$(optional_apt_lock_holder || true)"; [[ -n "$holder" ]]; do
    (( announced )) || { printf '[INFO] Waiting for another package manager to finish...\n'; announced=1; }
    if (( $(date +%s) >= deadline )); then printf '[FAIL] APT is still busy; installation was not started.\n' >&2; return 1; fi
    sleep 2
  done
  (( announced )) && printf '[ OK ] Package manager is available.\n'
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
optional_resolve_target() {
  local candidate=''
  if [[ -n "${STARTUP_TARGET_USER:-}" ]]; then candidate="$STARTUP_TARGET_USER"
  elif [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then candidate="$SUDO_USER"
  elif [[ -n "${SUDO_UID:-}" ]]; then candidate="$(getent passwd "$SUDO_UID" 2>/dev/null | cut -d: -f1 || true)"
  elif (( EUID != 0 )); then candidate="$(id -un)"
  else candidate="$(logname 2>/dev/null || true)"; fi
  [[ -n "$candidate" && "$candidate" != root ]] && getent passwd "$candidate" >/dev/null 2>&1 || return 1
  printf '%s\n' "$candidate"
}
target_user="$(optional_resolve_target || true)"
[[ -n "$target_user" ]] || { printf 'ERROR: Cannot determine a non-root target user; set STARTUP_TARGET_USER.\n' >&2; return 1; }
target_home="${STARTUP_TARGET_HOME:-$(getent passwd "$target_user" | cut -d: -f6)}"
target_uid="$(id -u "$target_user")"
target_gid="$(id -g "$target_user")"
[[ -d "$target_home" && "$target_home" != /root ]] || { printf 'ERROR: Invalid target home: %s\n' "$target_home" >&2; return 1; }
run_as_target() {
  local -a target_env=(env "HOME=$target_home" "USER=$target_user" "LOGNAME=$target_user" "XDG_CONFIG_HOME=$target_home/.config" "XDG_DATA_HOME=$target_home/.local/share")
  if [[ "$(id -un)" == "$target_user" ]]; then "${target_env[@]}" "$@"; elif (( EUID == 0 )); then runuser -u "$target_user" -- "${target_env[@]}" "$@"; else sudo -u "$target_user" -H "${target_env[@]}" "$@"; fi
}
optional_refresh() { case "$OPTIONAL_PM" in apt) optional_wait_for_apt && as_root timeout --foreground 10m apt-get -o Dpkg::Use-Pty=0 update;; pacman) as_root timeout --foreground 10m pacman -Sy --noconfirm;; esac; }
optional_install() { case "$OPTIONAL_PM" in apt) optional_wait_for_apt && as_root env DEBIAN_FRONTEND=noninteractive timeout --foreground 20m apt-get -o Dpkg::Use-Pty=0 install -y --no-install-recommends "$@";; pacman) as_root timeout --foreground 20m pacman -S --needed --noconfirm "$@";; esac; }

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
    curl -fsSL --retry 4 --retry-delay 2 --connect-timeout 20 --max-time 300 --output "$destination" "$url"
  else
    wget -q --https-only --tries=4 --timeout=20 --output-document="$destination" "$url"
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
