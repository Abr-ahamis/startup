#!/usr/bin/env bash
set -u

STYLE="${XDG_CONFIG_HOME:-$HOME/.config}/wofi/style.css"

# ============================================================
# Neo Sway Keybinding Menu
# ============================================================

WIDTH=300
HEIGHT=510

entries=(
  "@ Launching apps|"
  "Super + Enter|Terminal"
  "Super + Alt + Enter|Secondary terminal"
  "Super + Space / D|Application launcher"
  "Super + Alt + Space|Apps menu"
  "Super + Escape|System / power menu"
  "Super + K / Shift + F1|This shortcut guide"

  "@ Applications|"
  "Super + Shift + Enter|Browser"
  "Super + Shift + Alt + B|Secondary browser"
  "Super + Shift + F|File manager"
  "Super + Shift + T|Telegram"
  "Super + Shift + N|Text editor"
  "Super + Shift + C|VS Code"
  "Super + Shift + O|Obsidian"
  "Print|Screenshot"

  "@ Window controls|"
  "Super + W|Close focused window"
  "Ctrl + Alt + Delete|Close all windows"
  "Super + T|Toggle floating"
  "Super + O|Floating + sticky"
  "Super + F|Toggle fullscreen"
  "Super + J|Toggle horizontal / vertical split"
  "Super + E|Toggle horizontal / vertical split"
  "Super + S|Show scratchpad"
  "Super + Alt + S|Send window to scratchpad"
  "Super + A|Focus parent container"

  "@ Navigation|"
  "Super + Arrows|Focus direction"
  "Super + H / L|Focus left / right"
  "Super + Up Arrow|Focus up"
  "Super + Shift + Arrows|Move window"
  "Super + Shift + H J K L|Move left / down / up / right"
  "Alt + Tab / Shift + Tab|Next / previous window"
  "Ctrl + Alt + Tab|Next output"
  "Ctrl + Alt + Shift + Tab|Previous output"

  "@ Workspaces|"
  "Super + 1 … 0|Switch workspace"
  "Super + Shift + 1 … 0|Move window to workspace"
  "Super + Shift + Alt + 1 … 0|Move without switching"
  "Super + Tab / Shift + Tab|Next / previous workspace"
  "Super + Ctrl + Tab|Last workspace"
  "Super + Shift + Alt + Arrows|Move workspace to output"

  "@ Resize|"
  "Super + - / =|Grow / shrink width"
  "Super + Shift + - / =|Shrink / grow height"
  "Super + Alt + - / =|Small width resize"
  "Super + Ctrl + - / =|Large width resize"
  "Super + R|Resize mode"
  "Super + Left / Right Mouse|Move / resize"
  "Super + Mouse Wheel|Previous / next workspace"

  "@ System|"
  "Super + Ctrl + L|Lock screen"
  "Super + Ctrl + A|Audio + brightness"
  "Super + Ctrl + B|Bluetooth"
  "Super + Ctrl + W|Wi-Fi"
  "Super + Ctrl + P|Power menu"
  "Super + Ctrl + T|System monitor"
  "Super + Ctrl + C|Screenshot"
  "Super + Ctrl + V|Clipboard manager"
  "Super + Ctrl + N|Night Light"
  "Super + Ctrl + Delete|Turn displays off"

  "@ Notifications|"
  "Super + ,|Dismiss notification"
  "Super + Shift + ,|Dismiss all"
  "Super + Ctrl + ,|Pause / resume notifications"

  "@ Hardware|"
  "Volume Keys|Volume down / up / mute"
  "Alt + Volume Keys|Precise volume 1%"
  "Brightness Keys|Brightness down / up"
  "Shift + Brightness Keys|Minimum / maximum"
  "Alt + Brightness Keys|Precise brightness 1%"
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
    --location top right \
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