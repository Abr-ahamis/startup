#!/usr/bin/env bash
# Offline branch check for Arch, Debian, Ubuntu, and Kali. No package operation runs.
set -euo pipefail
root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"
for command in apt-get pacman; do printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/$command"; chmod 755 "$tmp/bin/$command"; done
PATH="$tmp/bin:$PATH"
source "$root_dir/lib/00-common.sh"; source "$root_dir/lib/10-distro.sh"; source "$root_dir/lib/20-packages.sh"
for spec in 'arch|arch|pacman' 'debian|debian|apt' 'ubuntu|debian|apt' 'kali|debian|apt'; do
  IFS='|' read -r id family manager <<< "$spec"
  file="$tmp/os-release"; printf 'ID=%s\nPRETTY_NAME=%s\n' "$id" "$id" > "$file"
  NEO_OS_RELEASE_FILE="$file" detect_distro
  [[ "$DISTRO_ID" == "$id" && "$DISTRO_FAMILY" == "$family" && "$PKG_MANAGER" == "$manager" ]]
  package_for network >/dev/null
  collect_required_packages
  [[ " ${REQUIRED_PACKAGES[*]} " == *' sway '* ]]
  [[ "$(printf '%s\n' "${REQUIRED_PACKAGES[@]}" | sort | uniq -d | wc -l)" -eq 0 ]]
done
printf '%s\n' 'distro matrix (Arch/Debian/Ubuntu/Kali): PASS'
