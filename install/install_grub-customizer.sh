#!/usr/bin/env bash
# Install GRUB Customizer through the native package source when available.
set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
optional_detect || exit 1

if command -v grub-customizer >/dev/null 2>&1; then
  echo 'GRUB Customizer is already installed.'
  exit 0
fi

optional_refresh || true
case "$OPTIONAL_PM" in
  apt)
    if ! optional_install grub-customizer; then
      echo 'GRUB Customizer is unavailable in the configured APT repositories.' >&2
      exit 1
    fi
    ;;
  pacman)
    aur_helper=''
    command -v yay >/dev/null 2>&1 && aur_helper=yay
    if [[ -z "$aur_helper" ]] && command -v paru >/dev/null 2>&1; then
      aur_helper=paru
    fi
    if [[ -z "$aur_helper" ]]; then
      echo 'GRUB Customizer is provided through the Arch AUR. Install yay or paru first, then rerun this installer.' >&2
      exit 1
    fi
    "$aur_helper" -S --needed --noconfirm grub-customizer
    ;;
esac

if command -v grub-customizer >/dev/null 2>&1; then
  echo 'GRUB Customizer installed successfully.'
else
  echo 'The package command completed, but grub-customizer was not found.' >&2
  exit 1
fi
