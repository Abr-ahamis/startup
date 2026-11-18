#!/usr/bin/env bash
# Ubuntu's APT package list. Ubuntu-specific package differences belong here.
# shellcheck source=lib/distros/default.sh
source "$SCRIPT_DIR/lib/distros/default.sh"
distro_package_for() {
  case "$1" in
    core) echo sway swaybg swayidle swaylock gtklock i3blocks wofi foot dex gammastep flameshot grim slurp pipewire pipewire-pulse wireplumber pulseaudio-utils pamixer wl-clipboard cliphist network-manager network-manager-gnome bluez blueman rfkill mate-polkit xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk dbus-user-session brightnessctl dunst libnotify-bin fontconfig jq curl gnome-keyring timeshift libsecret-1-0 libsecret-tools seahorse gnupg age apparmor bubblewrap cryptsetup build-essential pkg-config libsecret-1-dev libpam-gnome-keyring git grub2-common neovim;;
    *) default_distro_package_for "$1";;
  esac
}
