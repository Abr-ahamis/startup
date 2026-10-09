#!/usr/bin/env bash
# Lock the current Sway session with gtklock when available, else swaylock.
set -u

uid="$(id -u)"
home="${HOME:-$(getent passwd "$uid" | cut -d: -f6)}"
config_home="${XDG_CONFIG_HOME:-$home/.config}"

# swayidle's timeout and before-sleep hooks can fire close together. Avoid
# starting a second lockscreen while the user's existing one is active.
pgrep -u "$uid" -x gtklock >/dev/null 2>&1 && exit 0
pgrep -u "$uid" -x swaylock >/dev/null 2>&1 && exit 0

find_wallpaper() {
    local pid image i
    local -a args=()

    # Prefer the image currently passed to swaybg, so the lock matches Sway.
    while read -r pid; do
        [[ -r "/proc/$pid/cmdline" ]] || continue
        args=()
        mapfile -d '' -t args <"/proc/$pid/cmdline" || true
        for ((i = 0; i < ${#args[@]}; i++)); do
            case "${args[i]}" in
                -i|--image)
                    (( i + 1 < ${#args[@]} )) || continue
                    image="${args[i+1]}"
                    [[ -r "$image" ]] && { printf '%s\n' "$image"; return 0; }
                    ;;
                --image=*)
                    image="${args[i]#*=}"
                    [[ -r "$image" ]] && { printf '%s\n' "$image"; return 0; }
                    ;;
            esac
        done
    done < <(pgrep -u "$uid" -x swaybg 2>/dev/null || true)

    # Match the wallpaper selected by this project's Sway session setup.
    for image in \
        "$home/.local/share/backgrounds/startup/IMG1.jpg" \
        "$home/.local/share/backgrounds/startup/IMG2.jpg"; do
        [[ -r "$image" ]] && { printf '%s\n' "$image"; return 0; }
    done

    # If no Sway wallpaper is available, use the first common image in Pictures.
    for image in "$home"/Pictures/*; do
        [[ -f "$image" && -r "$image" ]] || continue
        case "${image,,}" in
            *.jpg|*.jpeg|*.png|*.webp|*.jxl) printf '%s\n' "$image"; return 0;;
        esac
    done
    return 1
}

wallpaper="$(find_wallpaper || true)"

if command -v gtklock >/dev/null 2>&1; then
    setup_script="$home/.local/bin/setup-gtklock.sh"
    [[ ! -x "$setup_script" ]] || "$setup_script" >/dev/null 2>&1 || true

    config_file="$config_home/gtklock/config.ini"
    if [[ -n "$wallpaper" ]]; then
        gtklock --daemonize --config "$config_file" --background "$wallpaper" && exit 0
    else
        gtklock --daemonize --config "$config_file" && exit 0
    fi
fi

if command -v swaylock >/dev/null 2>&1; then
    if [[ -n "$wallpaper" ]]; then
        exec swaylock --daemonize --image "$wallpaper" --scaling fill
    fi
    exec swaylock --daemonize --color 000000
fi

printf '%s\n' 'Neither gtklock nor swaylock is installed; cannot lock the Sway session.' >&2
exit 1
