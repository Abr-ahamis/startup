#!/usr/bin/env bash
# Set GDM greeter text to 80% using the system dconf database.
set -euo pipefail

backup_file() {
    local file="$1" backup_dir="/var/backups/neo-startup/gdm-scale"
    [[ -e "$file" ]] || return 0
    /usr/bin/install -d -m 700 "$backup_dir"
    /bin/cp -a -- "$file" "$backup_dir/$(basename "$file").$(date +%Y%m%d-%H%M%S).bak"
}

if (( EUID != 0 )); then
    command -v sudo >/dev/null 2>&1 || { echo 'sudo is required to configure GDM.' >&2; exit 1; }
    exec sudo -- "$0" "$@"
fi

display_manager="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)"
case "$display_manager" in
    */gdm.service|*/gdm3.service) ;;
    *) echo 'GDM is not selected as this system display manager; no changes made.' >&2; exit 1 ;;
esac
command -v dconf >/dev/null 2>&1 || { echo 'dconf is required to configure GDM appearance.' >&2; exit 1; }

profile=/etc/dconf/profile/gdm
database_dir=/etc/dconf/db/gdm.d
settings="$database_dir/90-startup-text-scale"
/usr/bin/install -d -m 755 /etc/dconf/profile "$database_dir"

if [[ ! -e "$profile" ]]; then
    backup_file "$profile"
    cat > "$profile" <<'EOF'
user-db:user
system-db:gdm
file-db:/usr/share/gdm/greeter-dconf-defaults
EOF
    chmod 644 "$profile"
elif ! grep -qxF 'system-db:gdm' "$profile"; then
    backup_file "$profile"
    printf '\nsystem-db:gdm\n' >> "$profile"
fi

if [[ ! -e "$settings" ]] || ! grep -qxF 'text-scaling-factor=0.8' "$settings"; then
    backup_file "$settings"
    temp="$(mktemp "$database_dir/.90-startup-text-scale.XXXXXX")"
    cat > "$temp" <<'EOF'
[org/gnome/desktop/interface]
text-scaling-factor=0.8
EOF
    chmod 644 "$temp"
    mv -f -- "$temp" "$settings"
fi

dconf update
printf '%s\n' 'GDM greeter text scale set to 0.8 (80%). GNOME does not expose a universal 0.8 overall UI scale here.'
