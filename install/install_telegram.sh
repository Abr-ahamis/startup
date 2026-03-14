#!/usr/bin/env bash

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

TARGET_USER="${STARTUP_TARGET_USER:-${SUDO_USER:-$USER}}"
HOME_DIR="${STARTUP_TARGET_HOME:-}"
if [ -z "$HOME_DIR" ]; then
    HOME_DIR="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || true)"
fi
if [ -z "$HOME_DIR" ]; then
    HOME_DIR="$HOME"
fi

BACKUP_TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="${HOME_DIR}/.BACKUPDV"
BACKUP_SESSION="${BACKUP_ROOT}/${BACKUP_TS}"

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
    $SUDO mkdir -p "$(dirname "$dest")"

    local base="$dest"
    local i=0
    while [ -e "$dest" ] || [ -L "$dest" ]; do
        i=$((i + 1))
        dest="${base}.dup${i}"
    done

    echo "🗄️  Backing up conflict: $path -> $dest"
    $SUDO mv -- "$path" "$dest"
}

rm -f tsetup.tar.xz
wget -q https://telegram.org/dl/desktop/linux -O /tmp/tsetup.tar.xz

echo "📦 Extracting Telegram..."
backup_conflict /opt/Telegram
sudo mkdir -p /opt/Telegram
sudo tar -xf /tmp/tsetup.tar.xz -C /opt/Telegram --strip-components=1

## Make it executable
sudo chmod +x /opt/Telegram/Telegram

# Add symlink if not present
if ! command -v telegram-desktop >/dev/null 2>&1; then
    backup_conflict /usr/local/bin/telegram-desktop
    sudo ln -s /opt/Telegram/Telegram /usr/local/bin/telegram-desktop
fi

#echo "🚀 Launching Telegram..."
/opt/Telegram/Telegram >/dev/null 2>&1 &
