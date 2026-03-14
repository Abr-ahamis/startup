#!/bin/bash

set -euo pipefail
trap 'echo -e "\033[0;31m❌ Error on line $LINENO: $BASH_COMMAND\033[0m"' ERR

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

echo -e "${CYAN}🔍 Preparing to install VirtualBox on Kali Linux...${RESET}"

TARGET_USER="${STARTUP_TARGET_USER:-${SUDO_USER:-$USER}}"
HOME_DIR="${STARTUP_TARGET_HOME:-}"
if [ -z "$HOME_DIR" ]; then
    HOME_DIR="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || true)"
fi
if [ -z "$HOME_DIR" ]; then
    HOME_DIR="$HOME"
fi

BACKUP_TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_SESSION="${HOME_DIR}/.BACKUPDV/${BACKUP_TS}"

backup_conflict() {
    local path="$1"
    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
        return 0
    fi

    local rel=""
    if [[ "$path" == "$HOME_DIR/"* ]]; then
        rel="${path#${HOME_DIR}/}"
    else
        rel="${path#/}"
    fi

    local dest="${BACKUP_SESSION}/${rel}"
    sudo mkdir -p "$(dirname "$dest")"

    local base="$dest"
    local i=0
    while [ -e "$dest" ] || [ -L "$dest" ]; do
        i=$((i + 1))
        dest="${base}.dup${i}"
    done

    echo -e "${CYAN}🗄️  Backing up conflict: ${path} -> ${dest}${RESET}"
    sudo mv -- "$path" "$dest"
}

# === Step 1: Remove old VirtualBox repo ===
echo -e "${YELLOW}🧹 Removing any existing VirtualBox repository...${RESET}"
backup_conflict /etc/apt/sources.list.d/virtualbox.list

# === Step 2: Add correct Bookworm repo ===
echo -e "${CYAN}🔗 Adding the correct VirtualBox repository (Debian Bookworm)...${RESET}"
echo "deb [signed-by=/usr/share/keyrings/vbox-archive-keyring.gpg] https://download.virtualbox.org/virtualbox/debian bookworm contrib" \
  | sudo tee /etc/apt/sources.list.d/virtualbox.list > /dev/null

# === Step 3: Add VirtualBox GPG key ===
echo -e "${CYAN}🔑 Downloading and adding VirtualBox GPG key...${RESET}"
backup_conflict /usr/share/keyrings/vbox-archive-keyring.gpg
wget -q https://www.virtualbox.org/download/oracle_vbox_2016.asc -O- \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/vbox-archive-keyring.gpg > /dev/null

# === Step 4: Update package lists ===
echo -e "${CYAN}🔄 Updating package lists...${RESET}"
sudo apt update -y

# === Step 5: Install dependencies ===
echo -e "${CYAN}🔧 Installing required packages...${RESET}"
sudo apt install -y build-essential dkms curl wget gnupg lsb-release

# === Step 6: Handle kernel headers ===
KERNEL_VERSION=$(uname -r)
if ! apt-cache search linux-headers-"$KERNEL_VERSION" | grep -q linux-headers-"$KERNEL_VERSION"; then
    echo -e "${YELLOW}⚠️ linux-headers for ${KERNEL_VERSION} not found. Installing generic headers instead...${RESET}"
    sudo apt install -y linux-headers-amd64 || true
else
    echo -e "${CYAN}📦 Installing linux-headers for ${KERNEL_VERSION}...${RESET}"
    sudo apt install -y linux-headers-"$KERNEL_VERSION"
fi

# === Step 7: Install VirtualBox ===
echo -e "${CYAN}📦 Installing VirtualBox from Bookworm repository...${RESET}"
sudo apt install -y virtualbox virtualbox-qt

# === Step 8: Configure kernel modules ===
echo -e "${CYAN}⚙️ Configuring VirtualBox kernel modules...${RESET}"
if [[ -x /sbin/vboxconfig ]]; then
    sudo /sbin/vboxconfig || true
elif [[ -x /usr/lib/virtualbox/vboxdrv.sh ]]; then
    sudo /usr/lib/virtualbox/vboxdrv.sh setup || true
else
    echo -e "${YELLOW}⚠️ VBox config script not found. Skipping manual module setup.${RESET}"
fi

# === Step 9: Add user to vboxusers ===
if id -nG "$TARGET_USER" | grep -qw "vboxusers"; then
    echo -e "${GREEN}👤 User '$TARGET_USER' already in vboxusers group.${RESET}"
else
    echo -e "${CYAN}➕ Adding user '$TARGET_USER' to vboxusers group...${RESET}"
    sudo usermod -aG vboxusers "$TARGET_USER"
    echo -e "${GREEN}✅ Added successfully. You may need to log out and back in.${RESET}"
fi

# === Step 10: Final Check ===
if command -v virtualbox >/dev/null 2>&1; then
    echo -e "${GREEN}✅ VirtualBox installed successfully.${RESET}"
else
    echo -e "${RED}❌ VirtualBox installation failed.${RESET}"
    exit 1
fi

echo ""
echo -e "${GREEN}🎉 Installation complete!${RESET}"
echo -e "${CYAN}🔁 Please reboot your system before running VirtualBox.${RESET}"
echo -e "${CYAN}🖥️ Launch VirtualBox with the command: ${YELLOW}virtualbox${RESET}"
