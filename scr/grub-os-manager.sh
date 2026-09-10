#!/usr/bin/env bash
#
# Neo GRUB OS Manager
#
# Detects:
#   - current host OS
#   - OSes found by os-prober
#   - existing GRUB menu entries
#   - UEFI bootloaders present on the EFI System Partition
#   - UEFI firmware boot entries (when efibootmgr is available)
#
# Then it:
#   - enables os-prober in /etc/default/grub
#   - regenerates GRUB
#   - shows detected and not-detected boot targets
#   - asks whether each missing EFI bootloader should be added
#   - asks what name should appear in GRUB
#   - creates /etc/grub.d/41-neo-os-entries
#   - preserves /etc/grub.d/40_custom
#   - regenerates and verifies grub.cfg
#
# UEFI custom entries use the EFI filesystem UUID instead of hard-coding
# (hd0,gpt2), making the generated entry more portable.
#

set -u
set -o pipefail

VERSION="1.0.0"
GRUB_DEFAULTS="/etc/default/grub"
GRUB_CFG="/boot/grub/grub.cfg"
CUSTOM_SCRIPT="/etc/grub.d/41-neo-os-entries"
BACKUP_DIR="/root/neo-grub-backups"
LOG_DIR="/var/log/neo-grub-os-manager"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/run-${TIMESTAMP}.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

info() { printf "${BLUE}[INFO]${RESET} %s\n" "$*"; }
ok() { printf "${GREEN}[ OK ]${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${RESET} %s\n" "$*"; }
err() { printf "${RED}[ERR ]${RESET} %s\n" "$*" >&2; }
section() { printf "\n${CYAN}==== %s ====${RESET}\n" "$*"; }
die() { err "$*"; exit 1; }

# ------------------------------------------------------------
# Root handling
# ------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    exec sudo -E bash "$0" "$@"
fi

mkdir -p "$BACKUP_DIR" "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

section "Neo GRUB OS Manager v${VERSION}"

# ------------------------------------------------------------
# Host detection
# ------------------------------------------------------------

if [[ ! -r /etc/os-release ]]; then
    die "/etc/os-release is missing; cannot detect the host OS."
fi

# shellcheck disable=SC1091
source /etc/os-release

HOST_ID="${ID:-unknown}"
HOST_NAME="${PRETTY_NAME:-$HOST_ID}"
HOST_LIKE="${ID_LIKE:-}"
HOST_ARCH="$(uname -m)"

if [[ -d /sys/firmware/efi ]]; then
    BOOT_MODE="UEFI"
else
    BOOT_MODE="Legacy BIOS"
fi

info "Host OS: ${HOST_NAME}"
info "Host ID: ${HOST_ID}"
info "Architecture: ${HOST_ARCH}"
info "Boot mode: ${BOOT_MODE}"

# ------------------------------------------------------------
# Command helpers
# ------------------------------------------------------------

have() {
    command -v "$1" >/dev/null 2>&1
}

require_cmd() {
    have "$1" || die "Required command not found: $1"
}

for cmd in awk grep sed find lsblk blkid findmnt grub-mkconfig; do
    require_cmd "$cmd"
done

if have update-grub; then
    UPDATE_GRUB_CMD=(update-grub)
elif [[ -x /usr/sbin/update-grub ]]; then
    UPDATE_GRUB_CMD=(/usr/sbin/update-grub)
else
    UPDATE_GRUB_CMD=(grub-mkconfig -o "$GRUB_CFG")
fi

run_update_grub() {
    "${UPDATE_GRUB_CMD[@]}"
}

# ------------------------------------------------------------
# Backups
# ------------------------------------------------------------

backup_file() {
    local file="$1"
    if [[ -e "$file" ]]; then
        cp -a "$file" "$BACKUP_DIR/$(basename "$file").${TIMESTAMP}.bak"
        ok "Backup created: $BACKUP_DIR/$(basename "$file").${TIMESTAMP}.bak"
    fi
}

backup_file "$GRUB_DEFAULTS"
backup_file "$CUSTOM_SCRIPT"

# ------------------------------------------------------------
# Package manager detection for os-prober
# ------------------------------------------------------------

install_os_prober() {
    if have os-prober; then
        return 0
    fi

    info "os-prober is not installed; attempting installation."

    if have apt-get; then
        export DEBIAN_FRONTEND=noninteractive
        if ! apt-get update; then
            warn "apt update returned an error; trying installation anyway."
        fi
        apt-get install -y os-prober

    elif have pacman; then
        pacman -Sy --needed --noconfirm os-prober

    elif have dnf; then
        dnf install -y os-prober

    elif have zypper; then
        zypper --non-interactive install os-prober

    elif have apk; then
        warn "Alpine normally does not use GRUB/os-prober in the same way; skipping os-prober installation."
        return 1

    else
        warn "No supported package manager found for automatic os-prober installation."
        return 1
    fi

    have os-prober
}

# ------------------------------------------------------------
# Enable os-prober safely
# ------------------------------------------------------------

enable_os_prober() {
    [[ -f "$GRUB_DEFAULTS" ]] || return 0

    if grep -Eq '^[[:space:]]*GRUB_DISABLE_OS_PROBER=' "$GRUB_DEFAULTS"; then
        sed -i 's/^[[:space:]]*GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' "$GRUB_DEFAULTS"
    elif grep -Eq '^[[:space:]]*#[[:space:]]*GRUB_DISABLE_OS_PROBER=' "$GRUB_DEFAULTS"; then
        sed -i 's/^[[:space:]]*#[[:space:]]*GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' "$GRUB_DEFAULTS"
    else
        printf '\nGRUB_DISABLE_OS_PROBER=false\n' >> "$GRUB_DEFAULTS"
    fi

    ok "GRUB_DISABLE_OS_PROBER=false is enabled."
}

OS_PROBER_AVAILABLE=0
if install_os_prober; then
    OS_PROBER_AVAILABLE=1
    enable_os_prober
else
    warn "os-prober could not be installed. Continuing with EFI/firmware detection where available."
fi

# ------------------------------------------------------------
# EFI System Partition detection
# ------------------------------------------------------------

EFI_MOUNT=""
EFI_SOURCE=""
EFI_UUID=""

if [[ "$BOOT_MODE" == "UEFI" ]]; then
    EFI_MOUNT="$(findmnt -n -o TARGET /boot/efi 2>/dev/null || true)"

    if [[ -z "$EFI_MOUNT" ]]; then
        # Pick the first mounted VFAT filesystem as a best-effort fallback.
        EFI_MOUNT="$(findmnt -rn -t vfat -o TARGET 2>/dev/null | head -n1 || true)"
    fi

    if [[ -n "$EFI_MOUNT" ]]; then
        EFI_SOURCE="$(findmnt -n -o SOURCE "$EFI_MOUNT" 2>/dev/null || true)"
        EFI_UUID="$(blkid -s UUID -o value "$EFI_SOURCE" 2>/dev/null || true)"
    fi

    if [[ -n "$EFI_SOURCE" && -n "$EFI_UUID" ]]; then
        ok "EFI mount: $EFI_MOUNT"
        ok "EFI partition: $EFI_SOURCE"
        ok "EFI filesystem UUID: $EFI_UUID"
    else
        warn "Could not identify a mounted EFI System Partition."
    fi
fi

# ------------------------------------------------------------
# Initial detection pass
# ------------------------------------------------------------

section "Detecting OSes"

OSPROBER_RAW=""
UPDATE_RAW=""

if [[ "$OS_PROBER_AVAILABLE" -eq 1 ]]; then
    info "Running os-prober..."
    OSPROBER_RAW="$(os-prober 2>&1 || true)"

    if [[ -n "$OSPROBER_RAW" ]]; then
        ok "os-prober returned results."
        printf '%s\n' "$OSPROBER_RAW"
    else
        info "os-prober did not report another OS."
    fi
fi

info "Regenerating GRUB to obtain the current detection result..."
if UPDATE_RAW="$(run_update_grub 2>&1)"; then
    ok "GRUB configuration generated successfully."
else
    warn "GRUB generation returned an error; showing output."
    printf '%s\n' "$UPDATE_RAW"
fi

if [[ ! -r "$GRUB_CFG" ]]; then
    die "$GRUB_CFG is missing after GRUB generation."
fi

# ------------------------------------------------------------
# Parse detected systems and current GRUB menu
# ------------------------------------------------------------

declare -a DETECTED_LABELS=()
declare -a GRUB_MENU_NAMES=()

declared_detected() {
    local label="$1"
    local item
    [[ -z "$label" ]] && return 0
    for item in "${DETECTED_LABELS[@]}"; do
        [[ "$item" == "$label" ]] && return 0
    done
    DETECTED_LABELS+=("$label")
}

# The running host is necessarily represented by its own GRUB installation in normal use.
declared_detected "${HOST_NAME} (current host)"

if [[ -n "$OSPROBER_RAW" ]]; then
    while IFS=: read -r device label type extra; do
        [[ -z "${label:-}" ]] && continue
        declared_detected "$label"
    done <<< "$OSPROBER_RAW"
fi

# Add labels from GRUB generation output.
if [[ -n "$UPDATE_RAW" ]]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^Found[[:space:]]+(.+)[[:space:]]+on[[:space:]]+(/dev/[^[:space:]]+) ]]; then
            declared_detected "${BASH_REMATCH[1]}"
        fi
    done <<< "$UPDATE_RAW"
fi

while IFS= read -r name; do
    [[ -n "$name" ]] && GRUB_MENU_NAMES+=("$name")
done < <(
    sed -nE \
        "s/^[[:space:]]*menuentry[[:space:]]+'([^']+)'.*/\1/p; \
         s/^[[:space:]]*menuentry[[:space:]]+\"([^\"]+)\".*/\1/p" \
        "$GRUB_CFG" | sort -u
)

printf '\nOS-prober / GRUB detection summary:\n'
for label in "${DETECTED_LABELS[@]}"; do
    printf '  [DETECTED] %s\n' "$label"
done

printf '\nCurrent GRUB menu entries:\n'
if [[ ${#GRUB_MENU_NAMES[@]} -eq 0 ]]; then
    printf '  (none parsed)\n'
else
    for name in "${GRUB_MENU_NAMES[@]}"; do
        printf '  - %s\n' "$name"
    done
fi

# ------------------------------------------------------------
# UEFI inventory
# ------------------------------------------------------------

declare -a EFI_FILES=()
declare -a EFI_LABELS=()

efi_label_from_path() {
    local rel="$1"
    local lower="${rel,,}"

    case "$lower" in
        /efi/microsoft/boot/bootmgfw.efi) echo "Windows Boot Manager" ;;
        /efi/limine/limine_x64.efi) echo "Limine (Omarchy)" ;;
        /efi/kali/grubx64.efi) echo "Kali GRUB" ;;
        /efi/ubuntu/shimx64.efi|/efi/ubuntu/grubx64.efi) echo "Ubuntu GRUB" ;;
        /efi/debian/shimx64.efi|/efi/debian/grubx64.efi) echo "Debian GRUB" ;;
        /efi/fedora/shimx64.efi|/efi/fedora/grubx64.efi) echo "Fedora GRUB" ;;
        /efi/opensuse*/shimx64.efi|/efi/opensuse*/grubx64.efi) echo "openSUSE GRUB" ;;
        /efi/arch/grubx64.efi) echo "Arch GRUB" ;;
        /efi/*/shimx64.efi|/efi/*/grubx64.efi)
            basename "$(dirname "$rel")" | sed 's/^./\U&/'
            ;;
        /efi/*/*.efi)
            basename "$(dirname "$rel")"
            ;;
        *) basename "$rel" ;;
    esac
}

if [[ "$BOOT_MODE" == "UEFI" && -n "$EFI_MOUNT" && -d "$EFI_MOUNT/EFI" ]]; then
    info "Scanning $EFI_MOUNT/EFI for EFI bootloaders..."

    while IFS= read -r -d '' file; do
        rel="${file#"$EFI_MOUNT"}"
        lower="${rel,,}"

        # Ignore generic boot fallback and utility binaries; those are not useful
        # as normal OS menu entries for this workflow.
        case "$lower" in
            /efi/boot/*.efi|/efi/tools/*.efi) continue ;;
        esac

        EFI_FILES+=("$file")
        EFI_LABELS+=("$(efi_label_from_path "$rel")")
    done < <(find "$EFI_MOUNT/EFI" -type f -iname '*.efi' -print0 2>/dev/null | sort -z)

    printf '\nEFI bootloaders found:\n'
    if [[ ${#EFI_FILES[@]} -eq 0 ]]; then
        printf '  (none)\n'
    else
        for i in "${!EFI_FILES[@]}"; do
            printf '  - %-30s %s\n' "${EFI_LABELS[$i]}" "${EFI_FILES[$i]#"$EFI_MOUNT"}"
        done
    fi
else
    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        warn "EFI filesystem scan unavailable."
    fi
fi

# ------------------------------------------------------------
# UEFI firmware entries
# ------------------------------------------------------------

if [[ "$BOOT_MODE" == "UEFI" && $(have efibootmgr; echo $?) -eq 0 ]]; then
    section "UEFI Firmware Entries"
    efibootmgr -v 2>/dev/null | sed -n '/^Boot[0-9A-Fa-f]/p' || true
fi

# ------------------------------------------------------------
# Missing EFI candidates
# ------------------------------------------------------------

declare -a MISSING_FILES=()
declare -a MISSING_LABELS=()

string_contains_ci() {
    local needle="${1,,}"
    shift || true
    local value
    for value in "$@"; do
        [[ -n "$value" && "${value,,}" == *"$needle"* ]] && return 0
    done
    return 1
}

for i in "${!EFI_FILES[@]}"; do
    file="${EFI_FILES[$i]}"
    label="${EFI_LABELS[$i]}"
    rel="${file#"$EFI_MOUNT"}"
    lower_rel="${rel,,}"

    # Never ask to add the host's own EFI loader merely because it is visible.
    host_lower="${HOST_ID,,}"
    case "$lower_rel" in
        "/efi/${host_lower}/"*)
            continue
            ;;
    esac

    # Known GRUB entries for the candidate already present?
    path_present=0
    label_present=0

    if grep -Fqi -- "$rel" "$GRUB_CFG" 2>/dev/null; then
        path_present=1
    fi

    if string_contains_ci "$label" "${GRUB_MENU_NAMES[@]}" "${DETECTED_LABELS[@]}"; then
        label_present=1
    fi

    if [[ $path_present -eq 0 && $label_present -eq 0 ]]; then
        MISSING_FILES+=("$file")
        MISSING_LABELS+=("$label")
    fi
done

# ------------------------------------------------------------
# Ask what to add
# ------------------------------------------------------------

section "OSes / Bootloaders Not Detected By GRUB"

declare -a SELECTED_FILES=()
declare -a SELECTED_NAMES=()

auto_add_candidate() {
    local file="$1"
    local label="$2"
    local rel="${file#"$EFI_MOUNT"}"
    local answer custom_name

    printf '\nCandidate:\n'
    printf '  Detected bootloader: %s\n' "$label"
    printf '  EFI path:            %s\n' "$rel"
    printf '  EFI partition:       %s\n' "$EFI_SOURCE"

    while true; do
        read -r -p "Add this bootloader to the GRUB menu? [y/N]: " answer
        answer="${answer:-N}"
        case "${answer,,}" in
            y|yes)
                custom_name="$label"
                read -r -p "Name to show in GRUB [$custom_name]: " entered_name
                [[ -n "$entered_name" ]] && custom_name="$entered_name"
                SELECTED_FILES+=("$file")
                SELECTED_NAMES+=("$custom_name")
                ok "Queued GRUB entry: $custom_name"
                break
                ;;
            n|no)
                info "Skipped: $label"
                break
                ;;
            *)
                warn "Please enter y or n."
                ;;
        esac
    done
}

if [[ ${#MISSING_FILES[@]} -eq 0 ]]; then
    ok "No additional EFI bootloaders were found that need a custom GRUB entry."
else
    for i in "${!MISSING_FILES[@]}"; do
        auto_add_candidate "${MISSING_FILES[$i]}" "${MISSING_LABELS[$i]}"
    done
fi

# ------------------------------------------------------------
# Generate safe separate GRUB script
# ------------------------------------------------------------

if [[ "$BOOT_MODE" == "UEFI" && -n "$EFI_UUID" && ${#SELECTED_FILES[@]} -gt 0 ]]; then
    cat > "$CUSTOM_SCRIPT" <<'HEADER'
#!/bin/sh
exec tail -n +3 "$0"

# Neo GRUB OS Manager generated entries.
# Existing /etc/grub.d/40_custom is intentionally preserved.

HEADER

    escape_single_quotes() {
        # GRUB/Bash-safe single-quoted string escaping: ' -> '\''
        printf '%s' "$1" | sed "s/'/'\\\\''/g"
    }

    for i in "${!SELECTED_FILES[@]}"; do
        file="${SELECTED_FILES[$i]}"
        name="${SELECTED_NAMES[$i]}"
        rel="${file#"$EFI_MOUNT"}"
        safe_name="$(escape_single_quotes "$name")"

        cat >> "$CUSTOM_SCRIPT" <<ENTRY
menuentry '$safe_name' --class os {
    insmod part_gpt
    insmod fat
    search --no-floppy --fs-uuid --set=neo_efi $EFI_UUID
    chainloader (\$neo_efi)$rel
}

ENTRY
    done

    chmod 755 "$CUSTOM_SCRIPT"
    ok "Created $CUSTOM_SCRIPT"
elif [[ ${#SELECTED_FILES[@]} -gt 0 ]]; then
    warn "Entries were selected, but no usable EFI UUID is available; no unsafe hard-coded EFI entry was written."
fi

# ------------------------------------------------------------
# Final GRUB regeneration
# ------------------------------------------------------------

section "Generating Final GRUB Configuration"

if ! run_update_grub; then
    err "GRUB generation failed. Existing configuration backups are in $BACKUP_DIR"
    exit 1
fi

ok "GRUB configuration generated."

# ------------------------------------------------------------
# Verify selected entries
# ------------------------------------------------------------

section "Verification"

VERIFY_FAILED=0

if [[ ${#SELECTED_NAMES[@]} -gt 0 ]]; then
    for name in "${SELECTED_NAMES[@]}"; do
        if grep -Fq "menuentry '$name'" "$GRUB_CFG" || grep -Fq "menuentry \"$name\"" "$GRUB_CFG"; then
            ok "Verified GRUB entry: $name"
        else
            warn "Could not verify GRUB entry: $name"
            VERIFY_FAILED=1
        fi
    done
else
    info "No new custom entries were selected."
fi

# Verify os-prober was actually enabled when available.
if [[ "$OS_PROBER_AVAILABLE" -eq 1 && -f "$GRUB_DEFAULTS" ]]; then
    if grep -Eq '^[[:space:]]*GRUB_DISABLE_OS_PROBER=false[[:space:]]*$' "$GRUB_DEFAULTS"; then
        ok "os-prober remains enabled in $GRUB_DEFAULTS"
    else
        warn "os-prober configuration could not be verified."
    fi
fi

# ------------------------------------------------------------
# Final summary
# ------------------------------------------------------------

section "Final Report"

printf 'Host OS             : %s\n' "$HOST_NAME"
printf 'Boot mode           : %s\n' "$BOOT_MODE"
printf 'GRUB configuration  : %s\n' "$GRUB_CFG"
printf 'Custom script       : %s\n' "$CUSTOM_SCRIPT"
printf 'Backup directory    : %s\n' "$BACKUP_DIR"
printf 'Log file            : %s\n' "$LOG_FILE"

if [[ -n "$EFI_SOURCE" ]]; then
    printf 'EFI partition       : %s\n' "$EFI_SOURCE"
fi
if [[ -n "$EFI_UUID" ]]; then
    printf 'EFI UUID            : %s\n' "$EFI_UUID"
fi

printf '\nDetected by os-prober / GRUB:\n'
for label in "${DETECTED_LABELS[@]}"; do
    printf '  [DETECTED] %s\n' "$label"
done

printf '\nAdded by Neo GRUB OS Manager:\n'
if [[ ${#SELECTED_NAMES[@]} -eq 0 ]]; then
    printf '  (none)\n'
else
    for name in "${SELECTED_NAMES[@]}"; do
        printf '  [ADDED] %s\n' "$name"
    done
fi

if [[ $VERIFY_FAILED -eq 0 ]]; then
    ok "GRUB OS management completed successfully."
else
    warn "GRUB was generated, but one or more custom entries could not be verified."
fi

printf '\nImportant: the script does not change UEFI BootOrder.\n'
printf 'Reboot and verify the GRUB menu before changing firmware boot order.\n'
