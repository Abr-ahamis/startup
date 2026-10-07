#!/usr/bin/env bash
set -u

STYLE="${XDG_CONFIG_HOME:-$HOME/.config}/wofi/style.css"

# ============================================================
# Neo Sway Keybinding Menu
# ============================================================

WIDTH=620
HEIGHT=820

entries=(
  "@ Launchers and applications|"
  "Super + Enter|Preferred terminal"
  "Super + Alt + Enter|Secondary terminal"
  "Super + Space|Application launcher"
  "Super + Alt + Space|Application launcher"
  "Super + D|Application launcher"
  "Super + K|Open this keybinding guide"
  "Shift + F1|Open this keybinding guide"
  "Super + Escape|Open system / power menu"
  "Super + Shift + Enter|Preferred browser"
  "Super + Shift + F|File manager"
  "Super + Shift + T|Telegram"
  "Super + Shift + N|Neovim"
  "Super + Shift + Alt + N|Text editor"
  "Super + Shift + C|VS Code / VSCodium"
  "Super + Shift + O|Obsidian"
  "Print|Screenshot"

  "@ Window management and focus|"
  "Super + W|Close focused window"
  "Ctrl + Alt + Delete|Close all application windows"
  "Super + T|Toggle floating / tiled"
  "Super + O|Toggle floating and sticky"
  "Super + F|Toggle fullscreen"
  "Super + A|Focus parent container"
  "Super + J|Toggle split layout orientation"
  "Super + E|Toggle split layout orientation"
  "Super + Left|Focus left window"
  "Super + Down|Focus lower window"
  "Super + Up|Focus upper window"
  "Super + Right|Focus right window"
  "Super + H|Focus left window"
  "Super + L|Focus right window"
  "Super + Shift + Left|Move window left"
  "Super + Shift + Down|Move window down"
  "Super + Shift + Up|Move window up"
  "Super + Shift + Right|Move window right"
  "Super + Shift + H|Move window left"
  "Super + Shift + J|Move window down"
  "Super + Shift + K|Move window up"
  "Super + Shift + L|Move window right"
  "Super + S|Show scratchpad"
  "Super + Alt + S|Move focused window to scratchpad"
  "Super + Left Mouse|Drag window"
  "Super + Right Mouse|Resize window"

  "@ Workspace and output navigation|"
  "Super + 1 … 9|Switch to workspace 1 … 9"
  "Super + 0|Switch to workspace 10"
  "Super + Shift + 1 … 9|Move window to workspace 1 … 9"
  "Super + Shift + 0|Move window to workspace 10"
  "Super + Shift + Alt + 1 … 9|Move window to workspace 1 … 9"
  "Super + Shift + Alt + 0|Move window to workspace 10"
  "Super + Tab|Next workspace"
  "Super + Shift + Tab|Previous workspace"
  "Super + Ctrl + Tab|Return to previous workspace"
  "Alt + Tab|Focus next window"
  "Alt + Shift + Tab|Focus previous window"
  "Ctrl + Alt + Tab|Focus next output"
  "Ctrl + Alt + Shift + Tab|Focus previous output"
  "Super + Shift + Alt + Left|Move workspace to left output"
  "Super + Shift + Alt + Down|Move workspace to lower output"
  "Super + Shift + Alt + Up|Move workspace to upper output"
  "Super + Shift + Alt + Right|Move workspace to right output"
  "Super + Mouse Wheel Up|Previous workspace"
  "Super + Mouse Wheel Down|Next workspace"

  "@ Resize windows|"
  "Super + R|Enter resize mode"
  "Resize mode: J|Shrink width by 4 px"
  "Resize mode: K|Grow height by 4 px"
  "Resize mode: L|Shrink height by 4 px"
  "Resize mode: Semicolon|Grow width by 4 px"
  "Resize mode: Left Arrow|Shrink width by 4 px"
  "Resize mode: Down Arrow|Grow height by 4 px"
  "Resize mode: Up Arrow|Shrink height by 4 px"
  "Resize mode: Right Arrow|Grow width by 4 px"
  "Resize mode: Enter|Exit resize mode"
  "Resize mode: Escape|Exit resize mode"
  "Resize mode: Super + R|Exit resize mode"
  "Super + Minus|Grow width by 10 px"
  "Super + Equal|Shrink width by 10 px"
  "Super + Shift + Minus|Shrink height by 10 px"
  "Super + Shift + Equal|Grow height by 10 px"
  "Super + Alt + Minus|Grow width by 5 px"
  "Super + Alt + Equal|Shrink width by 5 px"
  "Super + Ctrl + Minus|Grow width by 30 px"
  "Super + Ctrl + Equal|Shrink width by 30 px"

  "@ System menus and actions|"
  "Ctrl + Alt + R|Reload Sway configuration"
  "Ctrl + Alt + E|Exit Sway session"
  "Ctrl + Alt + L|Lock screen"
  "Ctrl + Alt + P|Open power menu"
  "Ctrl + Alt + W|Open Wi-Fi controller"
  "Ctrl + Alt + B|Open Bluetooth controller"
  "Ctrl + Alt + I|Open network information"
  "Ctrl + Alt + V|Open volume / brightness controls"
  "Super + Ctrl + L|Lock screen"
  "Super + Ctrl + Shift + L|Lock screen (alternate)"
  "Super + Ctrl + A|Open audio / brightness controls"
  "Super + Ctrl + B|Open Bluetooth controller"
  "Super + Ctrl + W|Open Wi-Fi controller"
  "Shift + Ctrl + P|Open terminal power menu"
  "Super + Ctrl + T|Open btop system monitor"
  "Super + Ctrl + C|Take screenshot"
  "Super + Ctrl + Delete|Turn off display outputs"
  "Super + Ctrl + N|Toggle night light"
  "Ctrl + Shift + Super + Q|Power off"
  "Ctrl + Shift + Super + A|Reboot"
  "Ctrl + Shift + Super + S|Suspend"
  "XF86RFKill|Toggle Wi-Fi radio"

  "@ Clipboard and notifications|"
  "Super + Ctrl + V|Open clipboard history"
  "Super + Comma|Dismiss latest notification"
  "Super + Shift + Comma|Dismiss all notifications"
  "Super + Ctrl + Comma|Toggle notification pause"

  "@ Audio and brightness keys|"
  "XF86AudioLowerVolume|Decrease volume by 5%"
  "XF86AudioRaiseVolume|Increase volume by 5%"
  "XF86AudioMute|Toggle audio mute"
  "Alt + XF86AudioLowerVolume|Decrease volume by 1%"
  "Alt + XF86AudioRaiseVolume|Increase volume by 1%"
  "XF86MonBrightnessDown|Decrease brightness by 2%"
  "XF86MonBrightnessUp|Increase brightness by 2%"
  "Shift + XF86MonBrightnessDown|Set brightness to minimum"
  "Shift + XF86MonBrightnessUp|Set brightness to maximum"
  "Alt + XF86MonBrightnessDown|Decrease brightness by 1%"
  "Alt + XF86MonBrightnessUp|Increase brightness by 1%"
)

# ------------------------------------------------------------
# Markup helpers
# ------------------------------------------------------------

escape_markup() {
    REPLY="$1"
    REPLY="${REPLY//&/\&amp;}"
    REPLY="${REPLY//</\&lt;}"
    REPLY="${REPLY//>/\&gt;}"
}

keycap() {
    escape_markup "$1"
    REPLY="<span background=\"#315273\" foreground=\"#f2f8ff\"><b> $REPLY </b></span>"
}

combo_markup() {
    local combo="$1"
    local output=""
    local part
    local -a parts=()

    combo="${combo// + /+}"

    IFS='+' read -ra parts <<< "$combo"

    for part in "${parts[@]}"; do
        part="${part#"${part%%[![:space:]]*}"}"
        part="${part%"${part##*[![:space:]]}"}"

        [[ -z "$part" ]] && continue

        [[ -n "$output" ]] &&
            output+=' <span foreground="#a9bed4"><b>+</b></span> '

        keycap "$part"
        output+="$REPLY"
    done

    REPLY="$output"
}

# ------------------------------------------------------------
# Build entries
# ------------------------------------------------------------

build_menu() {
    local entry combo action combo_rendered action_rendered

    for entry in "${entries[@]}"; do
        IFS='|' read -r combo action <<< "$entry"

        # Section header
        if [[ "$combo" == @* ]]; then
            printf \
                '<span foreground="#a6d5ff"><b> 󰘳  %s</b></span>\n' \
                "${combo#@ }"
            continue
        fi

        combo_markup "$combo"
        combo_rendered="$REPLY"
        escape_markup "$action"
        action_rendered="$REPLY"

        printf \
            '%s <span foreground="#b2c6da">→</span> <span foreground="#f1f5f9">%s</span>\n' \
            "$combo_rendered" "$action_rendered"
    done
}

# ------------------------------------------------------------
# Wofi
# ------------------------------------------------------------

build_menu |
"$HOME/.local/bin/wofi-popup.sh" \
    --dmenu \
    --show dmenu \
    --location top right \
    --allow-images \
    --allow-markup \
    --insensitive \
    --matching contains \
    --sort-order default \
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
