#!/usr/bin/env bash
set -u

# User settings. All size numbers are pixels unless noted.
MARGIN_TOP=20
MARGIN_RIGHT=40
MARGIN_BOTTOM=20
MARGIN_LEFT=20

# Fallback window size if Sway cannot report the focused monitor size.
WINDOW_WIDTH=880
WINDOW_HEIGHT=860

# Auto layout settings.
COLUMNS=3         # 0 = auto. Set 1, 2, 3, etc. to force columns.
MIN_COLUMNS=1      # Lower number gives wider cards and helps long text fit.
MAX_COLUMNS=10

# Card sizing.
CARD_MIN_FALLBACK=210   # Used if text-based width calculation is too small.
CHAR_WIDTH=8            # Rough character width estimate for window sizing.
CARD_EXTRA=120          # Extra space for spacing, symbols, and padding.

# Height sizing.
ROW_HEIGHT=32
WINDOW_PAD_Y=36

STYLE="${XDG_CONFIG_HOME:-$HOME/.config}/wofi/key-help.css"

output_name=""
output_width="$WINDOW_WIDTH"
output_height="$WINDOW_HEIGHT"

entries=(
  "@ Launching apps|"
  "Super + Enter|terminal"
  "Super + Alt + Enter|secondary terminal"
  "Super + Space / D|application launcher"
  "Super + Alt + Space|apps menu"
  "Super + Escape|system / power menu"
  "Super + K / Shift + F1|this shortcut guide"

  "Super + Shift + Enter|browser"
  "Super + Shift + Alt + B|secondary browser"
  "Super + Shift + F|file manager"
  "Super + Shift + T|Telegram"
  "Super + Shift + N|text editor"
  "Super + Shift + C|VS Code"
  "Super + Shift + O|Obsidian"
  "Print|screenshot"

  "@ Window controls|"
  "Super + W|close focused window"
  "Ctrl + Alt + Delete|close all windows (confirmation)"
  "Super + T|toggle floating"
  "Super + O|toggle floating and sticky"
  "Super + F|toggle fullscreen"
  "Super + J|toggle horizontal / vertical split"
  "Super + E|toggle horizontal / vertical split"
  "Super + S|show scratchpad"
  "Super + Alt + S|send focused window to scratchpad"
  "Super + A|focus parent container"

  "@ Navigating|"
  "Super + Arrows|focus in a direction"
  "Super + H / L|focus left / right"
  "Super + Up Arrow|focus up"
  "Super + Shift + Arrows|move window in a direction"
  "Super + Shift + H J K L|move left / down / up / right"
  "Alt + Tab / Shift + Tab|next / previous window"
  "Ctrl + Alt + Tab|next output"
  "Ctrl + Alt + Shift + Tab|previous output"

  "@ Workspaces and resize|"
  "Super + 1 … 0|switch workspace"
  "Super + Shift + 1 … 0|move window to workspace"
  "Super + Shift + Alt + 1 … 0|move window without switching workspace"
  "Super + Tab / Shift + Tab|next / previous workspace"
  "Super + Ctrl + Tab|last workspace"
  "Super + Shift + Alt + Arrows|move workspace to output"

  "Super + - / =|grow / shrink width"
  "Super + Shift + - / =|shrink / grow height"
  "Super + Alt + - / =|small width resize"
  "Super + Ctrl + - / =|large width resize"
  "Super + R|enter resize mode"
  "Super + Left / Right Mouse|move / resize window"
  "Super + Mouse Wheel|previous / next workspace"

  "@ System controls|"
  "Super + Ctrl + L|lock screen"
  "Super + Ctrl + A|audio and brightness menu"
  "Super + Ctrl + B|Bluetooth menu"
  "Super + Ctrl + W|Wi-Fi menu"
  "Super + Ctrl + P|power menu"
  "Super + Ctrl + T|system monitor"
  "Super + Ctrl + C|screenshot"
  "Super + Ctrl + V|clipboard manager"
  "Super + Ctrl + N|toggle Night Light"
  "Super + Ctrl + Delete|turn displays off"

  "@ Notifications|"
  "Super + ,|dismiss notification"
  "Super + Shift + ,|dismiss all notifications"
  "Super + Ctrl + ,|pause / resume notifications"

  "@ Hardware adjustments|"
  "Volume Keys|volume down / up / mute (5%)"
  "Alt + Volume Keys|precise volume down / up (1%)"
  "Brightness Keys|brightness down / up (2%)"
  "Shift + Brightness Keys|minimum / maximum brightness"
  "Alt + Brightness Keys|precise brightness down / up (1%)"
)

# Get the focused monitor size from Sway if possible.
if command -v swaymsg >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  output_rect=$(
    swaymsg -t get_outputs -r 2>/dev/null |
      jq -r '.[] | select(.focused) | "\(.name) \(.rect.width) \(.rect.height)"' 2>/dev/null |
      head -n 1
  )
  if [[ "$output_rect" =~ ^[^[:space:]]+[[:space:]][0-9]+[[:space:]][0-9]+$ ]]; then
    read -r output_name output_width output_height <<<"$output_rect"
  fi
fi

# Work out the usable screen area.
WIDTH=$((output_width - MARGIN_LEFT - MARGIN_RIGHT))
HEIGHT_LIMIT=$((output_height - MARGIN_TOP - MARGIN_BOTTOM))
((WIDTH < 320)) && WIDTH="$output_width"
((HEIGHT_LIMIT < 240)) && HEIGHT_LIMIT="$output_height"

entry_count="${#entries[@]}"

# Find the longest visible line so the cards can grow to fit the text better.
max_entry_len=0
for entry in "${entries[@]}"; do
  IFS='|' read -r combo action <<<"$entry"
  line_text="$combo = $action"
  line_len=${#line_text}
  (( line_len > max_entry_len )) && max_entry_len="$line_len"
done

# Estimate the minimum card width needed for the longest shortcut.
CARD_MIN=$((max_entry_len * CHAR_WIDTH + CARD_EXTRA))
((CARD_MIN < CARD_MIN_FALLBACK)) && CARD_MIN="$CARD_MIN_FALLBACK"

# Choose columns automatically unless the user forced a value.
if ! [[ "$COLUMNS" =~ ^[0-9]+$ ]] || ((COLUMNS == 0)); then
  COLUMNS=$((WIDTH / CARD_MIN))
fi

((COLUMNS < MIN_COLUMNS)) && COLUMNS="$MIN_COLUMNS"
((COLUMNS > MAX_COLUMNS)) && COLUMNS="$MAX_COLUMNS"
((COLUMNS > entry_count)) && COLUMNS="$entry_count"

# Compute window height from the number of rows.
LINES=$(((entry_count + COLUMNS - 1) / COLUMNS))
HEIGHT=$((LINES * ROW_HEIGHT + WINDOW_PAD_Y))
((HEIGHT > HEIGHT_LIMIT)) && HEIGHT="$HEIGHT_LIMIT"

XOFFSET="$MARGIN_LEFT"
YOFFSET="$MARGIN_TOP"

monitor_args=()
[[ -n "$output_name" ]] && monitor_args=(--monitor "$output_name")

keycap() {
  printf '<span background="#0f2942" foreground="#93c5fd"><b> %s </b></span>' "$1"
}

combo_markup() {
  local combo="$1"
  local out="" part
  local old_ifs="$IFS"

  IFS='+'
  read -ra parts <<<"${combo// + /+}"
  IFS="$old_ifs"

  for part in "${parts[@]}"; do
    part="$(printf '%s' "$part" | xargs)"
    [[ -n "$part" ]] || continue

    if [[ -n "$out" ]]; then
      out+=' <span foreground="#64748b">+</span> '
    fi

    out+="$(keycap "$part")"
  done

  printf '%s' "$out"
}

card() {
  local combo="$1"
  local action="$2"

  if [[ "$combo" == '@ '* ]]; then
    printf '<span foreground="#a78bfa"><b>%s</b></span>\n' "${combo#@ }"
    return
  fi

  printf '%s <span foreground="#64748b">=</span> <span foreground="#cbd5e1">%s</span>\n' \
    "$(combo_markup "$combo")" "$action"
}

shortcuts() {
  local entry combo action
  for entry in "${entries[@]}"; do
    IFS='|' read -r combo action <<<"$entry"
    card "$combo" "$action"
  done
}

shortcuts | wofi \
  --dmenu \
  --allow-markup \
  --hide-search \
  --insensitive \
  --prompt "Sway Shortcuts" \
  --style "$STYLE" \
  --width "$WIDTH" \
  --height "$HEIGHT" \
  --columns "$COLUMNS" \
  --lines "$LINES" \
  --location top_left \
  --xoffset "$XOFFSET" \
  --yoffset "$YOFFSET" \
  "${monitor_args[@]}" \
  --cache-file /dev/null \
  >/dev/null
