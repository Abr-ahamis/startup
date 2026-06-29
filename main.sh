#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# =========================================================
# Colors
# =========================================================
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[0;33m'
    BLUE=$'\033[0;34m'
    CYAN=$'\033[0;36m'
    RESET=$'\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    RESET=""
fi

log_info() { printf '%b\n' "${BLUE}[*]${RESET} $*"; }
log_ok()   { printf '%b\n' "${GREEN}[+]${RESET} $*"; }
log_warn() { printf '%b\n' "${YELLOW}[!]${RESET} $*"; }
log_fail() { printf '%b\n' "${RED}[-]${RESET} $*"; }

die() {
    log_fail "$*"
    exit 1
}

trap 'log_fail "Error on line $LINENO: $BASH_COMMAND"' ERR

step_num=0
step_total=10

step() {
    step_num=$((step_num + 1))
    printf '\n%b[%d/%d]%b %s\n' "${CYAN}" "$step_num" "$step_total" "${RESET}" "$1"
}

# =========================================================
# Paths
# =========================================================
readonly GRUB_SRC="grub"
readonly CONFIG_SRC="sway/.config"
readonly CONFIG_DEST="$HOME/.config"
readonly BIN_SRC="sway/.local/bin"
readonly BIN_DEST="$HOME/.local/bin"
readonly FONTS_SRC="sway/.local/share/fonts"
readonly FONTS_DEST="$HOME/.local/share/fonts"

readonly IMG1="wallpaper/IMG1.jpg"
readonly IMG2="wallpaper/IMG2.jpg"
readonly TARGET_DIR="/usr/share/backgrounds/kali"
readonly BACKUP_DIR="/usr/share/backgrounds/kali.bak"

# =========================================================
# Distro detection
# =========================================================
PKG_MGR=""
UPDATE_CMD=()
INSTALL_CMD=()
DISTRO_NAME="unknown"

detect_distro() {
    [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release"

    # shellcheck disable=SC1091
    source /etc/os-release
    DISTRO_NAME="${PRETTY_NAME:-unknown}"

    case "${ID:-unknown}" in
        kali|debian|ubuntu)
            PKG_MGR="apt"
            UPDATE_CMD=(sudo apt-get update -qq)
            INSTALL_CMD=(sudo apt-get install -y -qq)
            ;;
        arch|manjaro|endeavouros)
            PKG_MGR="pacman"
            UPDATE_CMD=(sudo pacman -Sy --noconfirm --quiet)
            INSTALL_CMD=(sudo pacman -S --noconfirm --needed --quiet)
            ;;
        *)
            die "Unsupported distro: ${DISTRO_NAME}"
            ;;
    esac

    log_info "Detected: ${DISTRO_NAME} (${PKG_MGR})"
}

# =========================================================
# Packages
# =========================================================
APT_PACKAGES=(
    sway
    swaybg
    swayidle
    swaylock
    waybar
    rofi
    foot
    dunst
    network-manager-gnome
    blueman
    gammastep
    brightnessctl
    pamixer
    wl-clipboard
    grim
    slurp
    dex
    git
    curl
    wget
    unzip
    pipx
)

ARCH_PACKAGES=(
    sway
    swaybg
    swayidle
    swaylock
    waybar
    rofi
    foot
    dunst
    network-manager-applet
    blueman
    gammastep
    brightnessctl
    pamixer
    wl-clipboard
    grim
    slurp
    dex
    git
    curl
    wget
    unzip
    python-pipx
)

# =========================================================
# Helpers
# =========================================================
package_installed() {
    local pkg="$1"
    case "$PKG_MGR" in
        apt) dpkg -s "$pkg" >/dev/null 2>&1 ;;
        pacman) pacman -Qq "$pkg" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

print_pkg_line() {
    local idx="$1"
    local total="$2"
    local msg="$3"
    printf '%b[%d/%d]%b %s\n' "${CYAN}" "$idx" "$total" "${RESET}" "$msg"
}

copy_items_verbose() {
    local src="$1"
    local dest="$2"
    local label="$3"

    if [[ ! -d "$src" ]]; then
        log_warn "$label source missing: $src"
        return 0
    fi

    mkdir -p "$dest"

    local found=0
    while IFS= read -r -d '' item; do
        found=1
        local name
        name="$(basename "$item")"

        if cp -a "$item" "$dest"/ >/dev/null 2>&1; then
            log_ok "$label: $name"
        else
            log_warn "failed to copy $label: $name"
        fi
    done < <(find "$src" -mindepth 1 -maxdepth 1 -print0)

    [[ "$found" -eq 0 ]] && log_warn "$label source is empty: $src"
}

# =========================================================
# Modules
# =========================================================
update_system() {
    log_info "Updating system..."
    local tmp
    tmp="$(mktemp)"

    if "${UPDATE_CMD[@]}" >"$tmp" 2>&1; then
        log_ok "System package list updated"
    else
        log_warn "system update failed"
        tail -n 6 "$tmp" | sed 's/^/      /'
    fi

    rm -f "$tmp"
}

install_tools() {
    log_info "Installing packages..."
    local items total i pkg
    case "$PKG_MGR" in
        apt) items=("${APT_PACKAGES[@]}") ;;
        pacman) items=("${ARCH_PACKAGES[@]}") ;;
        *) die "No package manager configured" ;;
    esac

    total="${#items[@]}"
    i=0

    for pkg in "${items[@]}"; do
        i=$((i + 1))

        if package_installed "$pkg"; then
            print_pkg_line "$i" "$total" "[+] $pkg already installed"
        else
            if "${INSTALL_CMD[@]}" "$pkg" >/dev/null 2>&1; then
                print_pkg_line "$i" "$total" "[+] $pkg installed"
            else
                print_pkg_line "$i" "$total" "[!] $pkg failed"
            fi
        fi
    done
}

install_pipx_tools() {
    log_info "Setting up pipx..."
    export PATH="$HOME/.local/bin:$PATH"
    pipx ensurepath >/dev/null 2>&1 || true

    if command -v autotiling >/dev/null 2>&1; then
        log_ok "autotiling already installed"
    else
        if pipx install autotiling >/dev/null 2>&1; then
            log_ok "autotiling installed"
        else
            log_warn "autotiling install failed"
        fi
    fi
}

install_grub() {
    log_info "Updating GRUB files..."
    if [[ -d "$GRUB_SRC" ]]; then
        if sudo cp -r "$GRUB_SRC" /boot/ >/dev/null 2>&1; then
            log_ok "GRUB files copied from $GRUB_SRC"
        else
            log_warn "GRUB copy failed"
        fi
    else
        log_warn "GRUB source missing: $GRUB_SRC"
    fi
}

install_configs() {
    log_info "Installing config files..."
    mkdir -p "$CONFIG_DEST"

    rm -rf \
        "$CONFIG_DEST/sway" \
        "$CONFIG_DEST/waybar" \
        "$CONFIG_DEST/rofi" \
        "$CONFIG_DEST/dunst" 2>/dev/null || true

    copy_items_verbose "$CONFIG_SRC" "$CONFIG_DEST" "Config"
}

fix_permissions() {
    log_info "Fixing config permissions..."

    local dirs=(
        "$CONFIG_DEST/sway/scripts"
        "$CONFIG_DEST/sway/i3blocks/scripts"
        "$BIN_DEST"
    )

    local d
    for d in "${dirs[@]}"; do
        if [[ -d "$d" ]]; then
            find "$d" -type f -exec chmod +x {} + 2>/dev/null || true
        fi
    done
}

install_binaries_fonts() {
    log_info "Copying local binaries and fonts..."
    mkdir -p "$BIN_DEST" "$FONTS_DEST"

    copy_items_verbose "$BIN_SRC" "$BIN_DEST" "BIN"
    copy_items_verbose "$FONTS_SRC" "$FONTS_DEST" "FONT"

    chmod +x "$BIN_DEST"/*.sh 2>/dev/null || true
}

backup_wallpapers() {
    log_info "Backing up wallpaper directory..."
    if [[ -d "$TARGET_DIR" ]]; then
        if [[ ! -d "$BACKUP_DIR" ]]; then
            if sudo cp -a "$TARGET_DIR" "$BACKUP_DIR" >/dev/null 2>&1; then
                log_ok "Wallpaper backup created"
            else
                log_warn "Wallpaper backup failed"
            fi
        else
            log_ok "Wallpaper backup already exists"
        fi
    else
        log_warn "Wallpaper directory not found yet"
    fi
}

rotate_wallpapers() {
    log_info "Rotating wallpapers..."

    [[ -f "$IMG1" ]] || die "Missing wallpaper source: $IMG1"
    [[ -f "$IMG2" ]] || die "Missing wallpaper source: $IMG2"

    sudo mkdir -p "$TARGET_DIR"

    mapfile -t files < <(
        find "$TARGET_DIR" -maxdepth 1 -type f \
            \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" \) \
            2>/dev/null || true
    )

    replaced_files=()
    local i=0
    local file name

    for file in "${files[@]}"; do
        name="$(basename "$file")"
        [[ "$name" == "wallpaper.jpg" ]] && continue

        if (( i % 2 == 0 )); then
            if sudo cp -f "$IMG1" "$file" >/dev/null 2>&1; then
                replaced_files+=("$name")
            fi
        else
            if sudo cp -f "$IMG2" "$file" >/dev/null 2>&1; then
                replaced_files+=("$name")
            fi
        fi

        i=$((i + 1))
    done

    if sudo cp -f "$IMG2" "$TARGET_DIR/wallpaper.jpg" >/dev/null 2>&1; then
        replaced_files+=("wallpaper.jpg (Static IMG2)")
    fi

    echo
    echo "[..] Total wallpapers replaced: ${#replaced_files[@]}"
    echo "Replaced files list:"
    for item in "${replaced_files[@]}"; do
        echo "  - $item"
    done
}

enable_services() {
    log_info "Enabling services..."
    systemctl --user daemon-reexec >/dev/null 2>&1 || true
    systemctl --user enable --now pipewire pipewire-pulse wireplumber >/dev/null 2>&1 || true
    log_ok "User services processed"
}

# =========================================================
# Start
# =========================================================
sudo -v >/dev/null 2>&1 || true
detect_distro

step "Checking wallpaper sources"
[[ -f "$IMG1" ]] || die "Missing wallpaper source: $IMG1"
[[ -f "$IMG2" ]] || die "Missing wallpaper source: $IMG2"
log_ok "Wallpaper sources found"

step "Updating system"
update_system

step "Installing tools"
install_tools

step "Setting up pipx tools"
install_pipx_tools

step "Updating GRUB files"
install_grub

step "Installing config files"
install_configs

step "Fixing config permissions"
fix_permissions

step "Copying local binaries and fonts"
install_binaries_fonts

step "Backing up wallpaper directory"
backup_wallpapers

step "Rotating wallpapers"
rotate_wallpapers

step "Enabling services"
enable_services

echo
echo "=========================================="
log_ok "INSTALL COMPLETE"
echo "=========================================="
echo "Reboot recommended"