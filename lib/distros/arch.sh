#!/usr/bin/env bash
# Arch's pacman package list. Arch-specific package names stay in this profile.
# shellcheck source=lib/distros/default.sh
source "$SCRIPT_DIR/lib/distros/default.sh"
distro_package_for() {
  case "$1" in
    core) echo sway swaybg swayidle swaylock gtklock i3blocks wofi foot dex gammastep flameshot grim slurp pipewire pipewire-pulse wireplumber libpulse pamixer wl-clipboard cliphist networkmanager bluez bluez-utils blueman rfkill polkit-gnome xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk dbus brightnessctl dunst libnotify fontconfig jq curl gnome-keyring timeshift libsecret seahorse gnupg age apparmor bubblewrap cryptsetup base-devel cmake pkgconf systemd-libs git neovim;;
    *) default_distro_package_for "$1";;
  esac
}
