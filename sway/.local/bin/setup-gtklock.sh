#!/usr/bin/env bash
# Create gtklock's per-user defaults without replacing existing customization.
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
gtklock_dir="$config_home/gtklock"
config_file="$gtklock_dir/config.ini"
style_file="$gtklock_dir/style.css"

umask 077
mkdir -p -- "$gtklock_dir"

if [[ ! -e "$config_file" ]]; then
  cat >"$config_file" <<EOF
[main]
gtk-theme=Adwaita-dark
style=$style_file
time-format=%H:%M
date-format=%A, %d %B %Y
EOF
  chmod 600 -- "$config_file"
  printf 'Created gtklock configuration: %s\n' "$config_file"
else
  printf 'Kept existing gtklock configuration: %s\n' "$config_file"
fi

if [[ ! -e "$style_file" ]]; then
  cat >"$style_file" <<'EOF'
/* gtklock supplies the wallpaper; keep the window transparent so it shows. */
window {
    background-color: transparent;
}

label {
    color: #f5f5f5;
}

entry {
    color: #f5f5f5;
    background-color: rgba(32, 33, 36, 0.82);
}
EOF
  chmod 644 -- "$style_file"
  printf 'Created gtklock style: %s\n' "$style_file"
else
  printf 'Kept existing gtklock style: %s\n' "$style_file"
fi
