# KeePassXC

The installer installs and verifies KeePassXC using each supported system's
package source. On Ubuntu it adds the KeePassXC PPA
(`ppa:phoerious/keepassxc`), refreshes APT, and installs `keepassxc`. On Debian
and Kali it uses the configured APT repositories; on Arch it uses pacman. If a
native package is unavailable and Snap is already installed, the installer
uses `snap install keepassxc` as a fallback. It does not install or enable
Snapd.

The Ubuntu PPA is added only when `/etc/os-release` identifies the system as
Ubuntu. Debian, Kali, Arch, and Linux Mint do not receive an Ubuntu PPA.

## Keyboard shortcut

**Super + Shift + P** opens KeePassXC in both Sway and GNOME. The Sway binding
uses the shared application launcher, which checks the native `keepassxc`
command and then `/snap/bin/keepassxc`.

To install the Snap manually on a system that already has Snapd:

```sh
sudo snap install keepassxc
```

For Ubuntu, the equivalent PPA setup performed by the installer is:

```sh
sudo add-apt-repository ppa:phoerious/keepassxc
sudo apt update
sudo apt install keepassxc
```
