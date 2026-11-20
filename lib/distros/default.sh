#!/usr/bin/env bash
# Family-level package defaults used by unlisted distributions and as fallback
# for exact OS profiles. Keep package manager variants explicit here.
default_distro_package_for() {
  case "$DISTRO_FAMILY:$1" in
    debian:python) echo python3;; arch:python) echo python;;
    debian:notify) echo libnotify-bin;; arch:notify) echo libnotify;;
    debian:network) echo network-manager;; arch:network) echo networkmanager;;
    debian:secret) echo libsecret-1-0 libsecret-tools;; arch:secret) echo libsecret;;
    debian:keyring_pam) echo libpam-gnome-keyring;; arch:keyring_pam) echo gnome-keyring;;
    debian:git_libsecret) echo build-essential pkg-config libsecret-1-dev;; arch:git_libsecret) echo base-devel pkgconf libsecret;;
    debian:portal|arch:portal) echo xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk;;
    debian:audio|arch:audio) echo pipewire pipewire-pulse wireplumber;;
    debian:clipboard|arch:clipboard) echo cliphist;; debian:bluetooth) echo bluez;; arch:bluetooth) echo bluez-utils;;
    debian:keepassxc|arch:keepassxc) echo keepassxc;;
    debian:protonvpn) echo proton-vpn-gnome-desktop;; arch:protonvpn) echo proton-vpn-gtk-app;;
    debian:core) echo sway swaybg swayidle swaylock gtklock i3blocks wofi foot dex gammastep flameshot grim slurp pipewire pipewire-pulse wireplumber pulseaudio-utils pamixer wl-clipboard cliphist network-manager bluez blueman rfkill mate-polkit xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk dbus-user-session brightnessctl dunst libnotify-bin fontconfig jq curl gnome-keyring timeshift libsecret-1-0 libsecret-tools seahorse gnupg age apparmor bubblewrap cryptsetup build-essential cmake pkg-config libudev-dev libsecret-1-dev libpam-gnome-keyring git grub2-common neovim;;
    arch:core) echo sway swaybg swayidle swaylock gtklock i3blocks wofi foot dex gammastep flameshot grim slurp pipewire pipewire-pulse wireplumber libpulse pamixer wl-clipboard cliphist networkmanager bluez bluez-utils blueman rfkill polkit-gnome xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk dbus brightnessctl dunst libnotify fontconfig jq curl gnome-keyring timeshift libsecret seahorse gnupg age apparmor bubblewrap cryptsetup base-devel cmake pkgconf systemd-libs git neovim;;
    *) return 1;;
  esac
}

# The default profile serves unlisted IDs directly. Exact OS profiles replace
# this dispatcher after sourcing the family mappings above.
distro_package_for() { default_distro_package_for "$@"; }
