#!/usr/bin/env bash
# Lock only an active Sway session with GTKlock. Never use this helper in GNOME.
set -u

if [[ -z "${SWAYSOCK:-}" || -z "${WAYLAND_DISPLAY:-}" ]] \
    || ! command -v swaymsg >/dev/null 2>&1 \
    || ! swaymsg -t get_version >/dev/null 2>&1; then
    printf '%s\n' 'Refusing to start GTKlock: no active Sway session was detected.' >&2
    exit 1
fi

uid="$(id -u)"
home="${HOME:-$(getent passwd "$uid" | cut -d: -f6)}"
config_home="${XDG_CONFIG_HOME:-$home/.config}"

# swayidle's timeout and before-sleep hooks can fire close together. Avoid
# starting a second lockscreen while the user's existing one is active.
pgrep -u "$uid" -x gtklock >/dev/null 2>&1 && exit 0

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

if ! command -v gtklock >/dev/null 2>&1; then
    printf '%s\n' 'GTKlock is not installed; run the startup installer before locking Sway.' >&2
    exit 1
fi

gtklock_args=(--daemonize)
config_file="$config_home/gtklock/config.ini"
[[ ! -r "$config_file" ]] || gtklock_args+=(--config "$config_file")
if [[ -n "$wallpaper" ]]; then
    gtklock_args+=(--background "$wallpaper")
fi

exec gtklock "${gtklock_args[@]}"
