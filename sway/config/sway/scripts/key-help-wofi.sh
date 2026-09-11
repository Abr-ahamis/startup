#!/usr/bin/env bash
set -u

STYLE="${XDG_CONFIG_HOME:-$HOME/.config}/wofi/style.css"

# ============================================================
# Neo Sway Keybinding Menu
# ============================================================

WIDTH=300
HEIGHT=510

entries=(

)

# ------------------------------------------------------------
# Markup helpers
# ------------------------------------------------------------

escape_markup() {
    printf '%s' "$1" |
        sed \
            -e 's/&/\&amp;/g' \
            -e 's/</\&lt;/g' \
            -e 's/>/\&gt;/g'
}

keycap() {
    local key
    key="$(escape_markup "$1")"

    printf \
        '<span background="#172b42" foreground="#8cc8ff"><b> %s </b></span>' \
        "$key"
}

combo_markup() {
    local combo="$1"
    local output=""
    local part

    combo="${combo// + /+}"

    IFS='+' read -ra parts <<< "$combo"

    for part in "${parts[@]}"; do
        part="$(printf '%s' "$part" | sed 's/^ *//;s/ *$//')"

        [[ -z "$part" ]] && continue

        [[ -n "$output" ]] &&
            output+=' <span foreground="#52657a">+</span> '

        output+="$(keycap "$part")"
    done

    printf '%s' "$output"
}

# ------------------------------------------------------------
# Build entries
# ------------------------------------------------------------

build_menu() {
    local entry combo action

    for entry in "${entries[@]}"; do
        IFS='|' read -r combo action <<< "$entry"

        # Section header
        if [[ "$combo" == @* ]]; then
            printf \
                '<span foreground="#72b7ff"><b> 󰘳  %s</b></span>\n' \
                "${combo#@ }"
            continue
        fi

        combo_markup "$combo"

        printf \
            ' <span foreground="#44576d">→</span> <span foreground="#c8d4e3">%s</span>\n' \
            "$(escape_markup "$action")"
    done
}

# ------------------------------------------------------------
# Wofi
# ------------------------------------------------------------

build_menu |
wofi \
    --dmenu \
    --show dmenu \
    --location top right 
    --allow-images \
    --allow-markup \
    --insensitive \
    --matching contains \
    --sort-order alphabetical \
    --gtk-dark \
    --prompt "󰍉  Search keybindings" \
    --style "$STYLE" \
    --width "$WIDTH" \
    --height "$HEIGHT" \
    --term foot \
    --xoffset 0 \
    --yoffset 0 \
    --hide-scroll \
    --cache-file /dev/null \
    --define layer=overlay \
    --define image_size=22 \
    >/dev/null