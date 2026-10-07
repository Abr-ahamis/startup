#!/usr/bin/env bash
# Install ble.sh for Bash history suggestions without changing shell rc files.
set -euo pipefail

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
installed="$data_home/blesh/ble.sh"
if [[ -r "$installed" ]]; then
  printf 'Bash suggestions are already installed at %s\n' "$installed"
  exit 0
fi

for dependency in curl tar xz; do
  command -v "$dependency" >/dev/null 2>&1 || {
    printf 'Cannot install Bash suggestions: %s is required.\n' "$dependency" >&2
    exit 1
  }
done

cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p -- "$cache_home" "$data_home"
stage="$(mktemp -d "$cache_home/startup-blesh.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
archive="$stage/ble-nightly.tar.xz"
url='https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz'

curl --fail --location --retry 2 --connect-timeout 15 --output "$archive" "$url"
tar -xJf "$archive" -C "$stage"
ble_script="$stage/ble-nightly/ble.sh"
[[ -r "$ble_script" ]] || {
  echo 'The ble.sh download did not contain the expected ble-nightly/ble.sh file.' >&2
  exit 1
}

bash "$ble_script" --install "$data_home"
[[ -r "$installed" ]] || {
  printf 'ble.sh did not install at the expected path: %s\n' "$installed" >&2
  exit 1
}
printf 'Bash suggestions installed. They use additional memory, so they are opt-in.\n'
printf 'To use them in a shell, run: STARTUP_SMART_SHELL=1 bash\n'
