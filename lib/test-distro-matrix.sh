#!/usr/bin/env bash
# Offline branch check for Arch, Debian, Ubuntu, and Kali. No package operation runs.
set -euo pipefail
root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"
for command in apt-get pacman; do printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/$command"; chmod 755 "$tmp/bin/$command"; done
PATH="$tmp/bin:$PATH"
source "$root_dir/lib/00-common.sh"; source "$root_dir/lib/10-distro.sh"; source "$root_dir/lib/20-packages.sh"
for spec in 'arch|arch|pacman' 'debian|debian|apt' 'ubuntu|debian|apt' 'linuxmint|debian|apt' 'kali|debian|apt'; do
  IFS='|' read -r id family manager <<< "$spec"
  file="$tmp/os-release"; printf 'ID=%s\nPRETTY_NAME=%s\n' "$id" "$id" > "$file"
  NEO_OS_RELEASE_FILE="$file" detect_distro
  [[ "$DISTRO_ID" == "$id" && "$DISTRO_FAMILY" == "$family" && "$PKG_MANAGER" == "$manager" ]]
  package_for network >/dev/null
  [[ "$DISTRO_PACKAGE_PROFILE" == "$root_dir/lib/distros/$id.sh" ]] || { printf 'Wrong profile selected for %s: %s\n' "$id" "$DISTRO_PACKAGE_PROFILE" >&2; exit 1; }
  core_packages="$(package_for core)"
  [[ " $core_packages " == *' gtklock '* ]] || { printf 'GTKlock missing from %s core packages\n' "$id" >&2; exit 1; }
  [[ " $core_packages " != *' grub-customizer '* ]] || { printf 'Optional grub-customizer is incorrectly required on %s\n' "$id" >&2; exit 1; }
  if [[ "$id" == kali ]]; then
    [[ " $core_packages " == *' rustscan '* && " $core_packages " == *' caido '* ]] || { printf 'Kali profile is missing RustScan or Caido\n' >&2; exit 1; }
    package_name_approved rustscan && package_name_approved caido || { printf 'Kali security tools were not approved by the package profile\n' >&2; exit 1; }
  else
    [[ " $core_packages " != *' rustscan '* && " $core_packages " != *' caido '* ]] || { printf 'Kali-only tools leaked into %s profile\n' "$id" >&2; exit 1; }
  fi
  if [[ "$family" == arch ]]; then
    [[ " $core_packages " == *' networkmanager '* && " $core_packages " == *' base-devel '* && " $core_packages " != *' network-manager '* ]] || { printf 'Arch-specific package names are wrong for %s\n' "$id" >&2; exit 1; }
    [[ " $core_packages " == *' cmake '* && " $core_packages " == *' systemd-libs '* ]] || { printf 'Arch battery monitor build dependencies are missing for %s\n' "$id" >&2; exit 1; }
  else
    [[ " $core_packages " == *' network-manager '* && " $core_packages " == *' build-essential '* && " $core_packages " != *' networkmanager '* ]] || { printf 'APT-family package names are wrong for %s\n' "$id" >&2; exit 1; }
    [[ " $core_packages " == *' cmake '* && " $core_packages " == *' libudev-dev '* ]] || { printf 'APT battery monitor build dependencies are missing for %s\n' "$id" >&2; exit 1; }
    if [[ "$id" == kali ]]; then
      [[ " $core_packages " == *' network-manager-applet '* && " $core_packages " != *' network-manager-gnome '* ]] || { printf 'Kali must use its available network-manager-applet package name\n' >&2; exit 1; }
    else
      [[ " $core_packages " == *' network-manager-gnome '* ]] || { printf 'Debian-family profile lost network-manager-gnome on %s\n' "$id" >&2; exit 1; }
    fi
  fi
  [[ "$(package_for keepassxc)" == keepassxc ]] || { printf 'KeePassXC package mapping failed for %s\n' "$id" >&2; exit 1; }
  package_name_approved keepassxc || { printf 'KeePassXC package rejected for %s\n' "$id" >&2; exit 1; }
  proton_package="$(package_for protonvpn)"
  if [[ "$family" == arch ]]; then
    [[ "$proton_package" == proton-vpn-gtk-app ]] || { printf 'Arch Proton VPN package mapping is wrong for %s\n' "$id" >&2; exit 1; }
  else
    [[ "$proton_package" == proton-vpn-gnome-desktop ]] || { printf 'APT Proton VPN package mapping is wrong for %s\n' "$id" >&2; exit 1; }
  fi
  package_name_approved "$proton_package" || { printf 'Proton VPN package rejected for %s\n' "$id" >&2; exit 1; }
  collect_required_packages
  [[ " ${REQUIRED_PACKAGES[*]} " == *' sway '* ]]
  [[ "$(printf '%s\n' "${REQUIRED_PACKAGES[@]}" | sort | uniq -d | wc -l)" -eq 0 ]]
done
file="$tmp/os-release"; printf 'ID=pop\nID_LIKE=ubuntu\nPRETTY_NAME=Pop\n' > "$file"
NEO_OS_RELEASE_FILE="$file" detect_distro
[[ "$DISTRO_ID" == pop && "$DISTRO_FAMILY" == debian && "$PKG_MANAGER" == apt ]]
package_for core >/dev/null
fallback_core="$(package_for core)"
[[ "$fallback_core" == *'grub2-common'* ]] || { printf 'Family fallback did not map the default Debian-family package list\n' >&2; exit 1; }
[[ "$DISTRO_PACKAGE_PROFILE" == "$root_dir/lib/distros/default.sh" ]] || { printf 'Unlisted OS did not use the default package profile\n' >&2; exit 1; }
[[ "$(package_for protonvpn)" == proton-vpn-gnome-desktop ]] || { printf 'Debian-family fallback Proton VPN mapping failed\n' >&2; exit 1; }
printf '%s\n' 'distro matrix (Arch/Debian/Ubuntu/Linux Mint/Kali/default fallback): PASS'
