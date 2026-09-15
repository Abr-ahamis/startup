#!/usr/bin/env bash
# Omarchy Hyprland setup
#
# Repository layout:
#
# startup/
# ├── wallpaper/
# │   ├── IMG1.jpg
# │   ├── IMG2.png
# │   └── ...
# └── scr/
#     └── omarchy-setup.sh
#
# This script:
#   - Configures Hyprland look-and-feel
#   - Configures personal keybindings
#   - Copies repository wallpapers to Omarchy backgrounds
#   - Copies repository wallpapers to ~/Pictures
#   - Backs up existing configuration before changing it
#
# IMPORTANT:
#   Run this script as your normal user.
#   Do NOT use sudo.
#
# Usage:
#   ./omarchy-setup.sh
#   ./omarchy-setup.sh --dry-run
#   ./omarchy-setup.sh --restore /path/to/backup
#   ./omarchy-setup.sh --help

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_NAME="Omarchy Hyprland Setup"
VERSION="1.1.0"

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------

# Directory containing this script:
# /home/neo/Projects/repo/startup/scr
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Repository root:
# /home/neo/Projects/repo/startup
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# Wallpaper directory is NEXT TO scr, not inside scr.
# /home/neo/Projects/repo/startup/wallpaper
WALLPAPER_DIR="${REPO_ROOT}/wallpaper"
DEFAULT_WALLPAPER="${WALLPAPER_DIR}/IMG1.jpg"
DOCKER_SOURCE_DIR="${REPO_ROOT}/scr/Docker"
WORK_DIR="${HOME}/Work"
DOCKER_DEST_DIR="${WORK_DIR}/Docker"

HYPR_DIR="${HOME}/.config/hypr"
OMARCHY_BG_DIR="${HOME}/.config/omarchy/backgrounds/tokyo-night"
PICTURES_DIR="${HOME}/Pictures"

STATE_ROOT="${HOME}/.local/state/omarchy-setup"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${STATE_ROOT}/${TIMESTAMP}"
LOG_FILE="${BACKUP_DIR}/install.log"

LOOKNFEEL_FILE="${HYPR_DIR}/looknfeel.lua"
BINDINGS_FILE="${HYPR_DIR}/bindings.lua"

DRY_RUN=0
RESTORE_DIR=""

# ------------------------------------------------------------
# Output helpers
# ------------------------------------------------------------

info() {
    printf '[INFO] %s\n' "$*"
}

ok() {
    printf '[ OK ] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

die() {
    printf '[FAIL] %s\n' "$*" >&2
    exit 1
}

# ------------------------------------------------------------
# Command runner
# ------------------------------------------------------------

run() {
    if (( DRY_RUN )); then
        printf '[DRY ]'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

# ------------------------------------------------------------
# Usage
# ------------------------------------------------------------

usage() {
    cat <<USAGE
${SCRIPT_NAME} v${VERSION}

Configure the requested Omarchy/Hyprland look-and-feel,
personal bindings, and wallpapers.

Repository layout:

    startup/
  ├── wallpaper/
  │   ├── IMG1.jpg
  │   ├── IMG2.png
  │   └── ...
  └── scr/
      └── omarchy-setup.sh

Usage:

  $0
      Apply configuration

  $0 --dry-run
      Show what would be changed without modifying anything

  $0 --restore DIR
      Restore a previous backup

  $0 --help
      Show this help

IMPORTANT:
  Do NOT run this script with sudo.
USAGE
}

# ------------------------------------------------------------
# Argument parsing
# ------------------------------------------------------------

parse_args() {
    while (($#)); do
        case "$1" in
            --dry-run)
                DRY_RUN=1
                shift
                ;;

            --restore)
                [[ $# -ge 2 ]] || die "--restore requires a backup directory."
                RESTORE_DIR="$2"
                shift 2
                ;;

            --help|-h)
                usage
                exit 0
                ;;

            *)
                die "Unknown argument: $1"
                ;;
        esac
    done
}

# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------

init_log() {
    if (( DRY_RUN )); then
        return
    fi

    mkdir -p "$BACKUP_DIR"
    : > "$LOG_FILE"

    exec > >(tee -a "$LOG_FILE") 2>&1
}

# ------------------------------------------------------------
# Requirement checks
# ------------------------------------------------------------

check_requirements() {
    [[ -d "$SCRIPT_DIR" ]] ||
        die "Could not determine script directory."

    [[ -d "$REPO_ROOT" ]] ||
        die "Repository root not found: $REPO_ROOT"

    [[ -d "$WALLPAPER_DIR" ]] ||
        die "Wallpaper directory not found: $WALLPAPER_DIR"

    [[ -f "$DEFAULT_WALLPAPER" ]] ||
        die "Default wallpaper not found: $DEFAULT_WALLPAPER"

    [[ -d "$DOCKER_SOURCE_DIR" ]] ||
        die "Docker source folder not found: $DOCKER_SOURCE_DIR"

    [[ -d "$HOME" ]] ||
        die "Home directory not found: $HOME"

    # Prevent accidental root execution.
    if [[ "${EUID}" -eq 0 ]]; then
        die "Run this script as your normal user, not with sudo: ./omarchy-setup.sh"
    fi

    if command -v hyprctl >/dev/null 2>&1; then
        info "hyprctl found."
    else
        warn "hyprctl not found; configuration will still be written."
    fi

    if command -v omarchy >/dev/null 2>&1; then
        info "omarchy command found."
    else
        warn "omarchy command not found; continuing."
    fi

    ok "Repository and wallpaper paths verified: $DEFAULT_WALLPAPER"
}

# ------------------------------------------------------------
# Backup
# ------------------------------------------------------------

backup_file() {
    local src="$1"
    local label="$2"

    if [[ -e "$src" ]]; then
        mkdir -p "$BACKUP_DIR"

        info "Backing up: $src"

        run cp -a -- "$src" "${BACKUP_DIR}/${label}"
    fi
}

backup_targets() {
    info "Backing up existing Hyprland configuration..."

    backup_file "$LOOKNFEEL_FILE" "looknfeel.lua.bak"
    backup_file "$BINDINGS_FILE" "bindings.lua.bak"

    if ! (( DRY_RUN )); then
        {
            printf 'Timestamp: %s\n' "$TIMESTAMP"
            printf 'Script directory: %s\n' "$SCRIPT_DIR"
            printf 'Repository root: %s\n' "$REPO_ROOT"
            printf 'Wallpaper directory: %s\n' "$WALLPAPER_DIR"
            printf 'Docker source: %s\n' "$DOCKER_SOURCE_DIR"
            printf 'Docker destination: %s\n' "$DOCKER_DEST_DIR"
            printf 'Looknfeel: %s\n' "$LOOKNFEEL_FILE"
            printf 'Bindings: %s\n' "$BINDINGS_FILE"
            printf 'Omarchy backgrounds: %s\n' "$OMARCHY_BG_DIR"
            printf 'Pictures: %s\n' "$PICTURES_DIR"
        } > "${BACKUP_DIR}/manifest.txt"

        chmod 600 "${BACKUP_DIR}/manifest.txt"
    fi
}

# ------------------------------------------------------------
# Hyprland look and feel
# ------------------------------------------------------------

write_looknfeel() {
    run mkdir -p "$HYPR_DIR"

    if (( DRY_RUN )); then
        cat <<'LUA'
--- would write ~/.config/hypr/looknfeel.lua ---

-- Neo look'n'feel overrides
-- Managed by omarchy-setup.sh

hl.config({
    general = {
        gaps_in = 1,
        gaps_out = 2,
        border_size = 0,
        layout = "dwindle",
    },
})

hl.config({
    decoration = {
        rounding = 8,

        active_opacity = 0.85,
        inactive_opacity = 0.70,

        blur = {
            enabled = true,
            size = 3,
            passes = 1,
        },
    },
})
LUA
        return
    fi

    cat > "$LOOKNFEEL_FILE" <<'LUA'
-- Neo look'n'feel overrides
-- Managed by omarchy-setup.sh

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
hl.config({
    general = {
        -- Minimal gaps and no borders.
        gaps_in = 1,
        gaps_out = 2,
        border_size = 0,

        -- Use Hyprland's standard dwindle layout.
        layout = "dwindle",
    },
})

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
hl.config({
    decoration = {
        -- Rounded corners.
        rounding = 8,

        -- Slight transparency.
        active_opacity = 0.85,
        inactive_opacity = 0.70,

        -- Light blur.
        blur = {
            enabled = true,
            size = 3,
            passes = 1,
        },
    },
})
LUA

    chmod 600 "$LOOKNFEEL_FILE"

    ok "Wrote $LOOKNFEEL_FILE"
}

# ------------------------------------------------------------
# Keybindings
# ------------------------------------------------------------

write_bindings() {
    run mkdir -p "$HYPR_DIR"

    if (( DRY_RUN )); then
        cat <<'LUA'
--- would write ~/.config/hypr/bindings.lua ---

-- Neo personal keybindings

o.bind("SUPER + SHIFT + T", nil, "/opt/Telegram/./Telegram")
o.bind("SUPER + SHIFT + L", "exec", "gnome-text-editor")
o.bind("SUPER + SHIFT + C", nil, "code")
LUA
        return
    fi

    cat > "$BINDINGS_FILE" <<'LUA'
-- Neo personal keybindings
-- Managed by omarchy-setup.sh

-- Telegram
o.bind("SUPER + SHIFT + T", nil, "/opt/Telegram/./Telegram")

-- GNOME Text Editor
o.bind("SUPER + SHIFT + L", "exec", "gnome-text-editor")

-- VS Code
o.bind("SUPER + SHIFT + C", nil, "code")
LUA

    chmod 600 "$BINDINGS_FILE"

    ok "Wrote $BINDINGS_FILE"
}

# ------------------------------------------------------------
# Wallpapers
# ------------------------------------------------------------

copy_wallpapers() {
    local wallpapers=()

    # Find regular files directly inside wallpaper/.
    while IFS= read -r -d '' file; do
        wallpapers+=("$file")
    done < <(
        find "$WALLPAPER_DIR" \
            -maxdepth 1 \
            -type f \
            -print0 |
        sort -z
    )

    ((${#wallpapers[@]} > 0)) ||
        die "No wallpaper files found in: $WALLPAPER_DIR"

    info "Found ${#wallpapers[@]} wallpaper(s)."

    run mkdir -p "$OMARCHY_BG_DIR"
    run mkdir -p "$PICTURES_DIR"

    local src
    local base

    for src in "${wallpapers[@]}"; do
        base="$(basename -- "$src")"

        info "Copying wallpaper: $base"

        run cp -f -- "$src" "$OMARCHY_BG_DIR/$base"
        run cp -f -- "$src" "$PICTURES_DIR/$base"
    done

    ok "Copied ${#wallpapers[@]} wallpaper(s) to:"
    ok "  $OMARCHY_BG_DIR"
    ok "  $PICTURES_DIR"
}

copy_docker_folder() {
    [[ -d "$DOCKER_SOURCE_DIR" ]] ||
        die "Docker source folder not found: $DOCKER_SOURCE_DIR"

    run mkdir -p "$DOCKER_DEST_DIR"
    run cp -a -- "$DOCKER_SOURCE_DIR/." "$DOCKER_DEST_DIR/"
    ok "Docker folder copied to: $DOCKER_DEST_DIR"
}

# ------------------------------------------------------------
# Validation
# ------------------------------------------------------------

validate_files() {
    if (( DRY_RUN )); then
        return
    fi

    [[ -f "$LOOKNFEEL_FILE" ]] ||
        die "looknfeel.lua was not created."

    [[ -f "$BINDINGS_FILE" ]] ||
        die "bindings.lua was not created."

    grep -q 'layout = "dwindle"' "$LOOKNFEEL_FILE" ||
        die "looknfeel.lua validation failed: layout."

    grep -q 'gaps_in = 1' "$LOOKNFEEL_FILE" ||
        die "looknfeel.lua validation failed: gaps_in."

    grep -q 'gaps_out = 2' "$LOOKNFEEL_FILE" ||
        die "looknfeel.lua validation failed: gaps_out."

    grep -q 'border_size = 0' "$LOOKNFEEL_FILE" ||
        die "looknfeel.lua validation failed: border_size."

    grep -q 'active_opacity = 0.85' "$LOOKNFEEL_FILE" ||
        die "looknfeel.lua validation failed: active opacity."

    grep -q 'inactive_opacity = 0.70' "$LOOKNFEEL_FILE" ||
        die "looknfeel.lua validation failed: inactive opacity."

    grep -q 'rounding = 8' "$LOOKNFEEL_FILE" ||
        die "looknfeel.lua validation failed: rounding."

    grep -q 'o.bind("SUPER + SHIFT + T"' "$BINDINGS_FILE" ||
        die "bindings.lua validation failed: Telegram binding."

    grep -q 'o.bind("SUPER + SHIFT + L"' "$BINDINGS_FILE" ||
        die "bindings.lua validation failed: editor binding."

    grep -q 'o.bind("SUPER + SHIFT + C"' "$BINDINGS_FILE" ||
        die "bindings.lua validation failed: code binding."

    ok "Configuration files validated."
}

# ------------------------------------------------------------
# Reload Hyprland
# ------------------------------------------------------------

reload_hyprland() {
    if (( DRY_RUN )); then
        info "Would reload Hyprland with: hyprctl reload"
        return
    fi

    if command -v hyprctl >/dev/null 2>&1 &&
       [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then

        if hyprctl reload >/dev/null 2>&1; then
            ok "Hyprland configuration reloaded."
            return
        fi
    fi

    warn "Could not reload Hyprland automatically."
    warn "If needed, run: hyprctl reload"
}

# ------------------------------------------------------------
# Restore
# ------------------------------------------------------------

restore() {
    [[ -n "$RESTORE_DIR" ]] ||
        die "Restore directory was not specified."

    [[ -d "$RESTORE_DIR" ]] ||
        die "Backup directory not found: $RESTORE_DIR"

    local look_backup="${RESTORE_DIR}/looknfeel.lua.bak"
    local bind_backup="${RESTORE_DIR}/bindings.lua.bak"

    info "Restoring from:"
    info "$RESTORE_DIR"

    if [[ -f "$look_backup" ]]; then
        mkdir -p "$HYPR_DIR"

        cp -a -- "$look_backup" "$LOOKNFEEL_FILE"

        ok "Restored looknfeel.lua"
    else
        warn "No looknfeel.lua backup found."
    fi

    if [[ -f "$bind_backup" ]]; then
        mkdir -p "$HYPR_DIR"

        cp -a -- "$bind_backup" "$BINDINGS_FILE"

        ok "Restored bindings.lua"
    else
        warn "No bindings.lua backup found."
    fi

    reload_hyprland

    ok "Restore complete."
}

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

print_summary() {
    cat <<SUMMARY

============================================================
${SCRIPT_NAME} v${VERSION}
============================================================

Repository:
  ${REPO_ROOT}

Script:
    ${SCRIPT_DIR}/omarchy-setup.sh

Hypr config:
  ${HYPR_DIR}

Look'n'feel:
  ${LOOKNFEEL_FILE}

Bindings:
  ${BINDINGS_FILE}

Wallpaper source:
  ${WALLPAPER_DIR}

Tokyo Night:
  ${OMARCHY_BG_DIR}

Pictures:
  ${PICTURES_DIR}

Backup:
  ${BACKUP_DIR}

Applied look'n'feel:
  gaps_in          = 1
  gaps_out         = 2
  border_size      = 0
  layout           = dwindle
  rounding         = 8
  active_opacity   = 0.85
  inactive_opacity = 0.70
  blur             = enabled / size 3 / passes 1

Applied bindings:
  Super+Shift+T -> Telegram
  Super+Shift+L -> GNOME Text Editor
  Super+Shift+C -> code

============================================================
Done.
============================================================

SUMMARY
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

main() {
    parse_args "$@"
    init_log

    if [[ -n "$RESTORE_DIR" ]]; then
        restore
        exit 0
    fi

    check_requirements
    backup_targets
    write_looknfeel
    write_bindings
    copy_docker_folder
    copy_wallpapers
    validate_files
    reload_hyprland
    print_summary
}

main "$@"
