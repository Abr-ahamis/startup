#!/usr/bin/env bash
# One-shot Proton VPN install fix for neo/Ubuntu 24.04
# Workaround for the Proton 1.0.8 package bug: dpkg -i installs the release
# package but never writes /etc/apt/sources.list.d/protonvpn-stable.sources.
# We create the file manually, then apt update + install the app.
set -u

SOURCES=/etc/apt/sources.list.d/protonvpn-stable.sources
KEYRING=/usr/share/keyrings/protonvpn-stable-archive-keyring.gpg

echo "== [1/4] Ensure Proton repo file exists =="
if [[ -f "$SOURCES" ]]; then
  echo "OK: $SOURCES already present"
else
  echo "Creating $SOURCES ..."
  sudo tee "$SOURCES" >/dev/null <<'PROTON_SOURCES_EOF'
Types: deb
URIs: https://repo.protonvpn.com/debian
Suites: stable
Components: main
Signed-By: /usr/share/keyrings/protonvpn-stable-archive-keyring.gpg
PROTON_SOURCES_EOF
fi

echo
echo "== [2/4] Verify keyring and repo file =="
if [[ -f "$KEYRING" ]]; then
  echo "OK: keyring present"
else
  echo "ERROR: keyring missing at $KEYRING - reinstall release package first" >&2
  exit 1
fi
cat "$SOURCES"

echo
echo "== [3/4] Update package lists =="
sudo apt update

echo
echo "== [4/4] Install Proton VPN GUI + CLI =="
sudo apt install -y proton-vpn-gnome-desktop

echo
echo "DONE. Proton VPN is installed."
