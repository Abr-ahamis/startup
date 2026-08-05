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
ROW_HEIGHT=48
WINDOW_PAD_Y=36

STYLE="${XDG_CONFIG_HOME:-$HOME/.config}/wofi/key-help.css"

output_name=""
output_width="$WINDOW_WIDTH"
output_height="$WINDOW_HEIGHT"

entries=(
  "Super + Enter|foot"
  "Super + Shift + Enter|gnome-ter"
  "Super + D|menu"
  "Shift + F1|help"

  "WIN + Shift + E|Nemo"
  "WIN + Shift + F|Firefox"
  "WIN + Shift + B|Brave"
  "WIN + Shift + T|Telegram"
  "WIN + Shift + N|Gnome-text-editor"
  "WIN + Shift + S|Flameshot"
  "WIN + Shift + C|Vscode"

  "Ctrl + Alt + R|reload sway"
  "Ctrl + Alt + E|exit sway"
  "Ctrl + Alt + L|lock"
  "Ctrl + Alt + P|power menu"

  "Super + Shift + Q|kill focused window"
  "Super + F|fullscreen"
  "Super + Shift + Space|toggle floating"
  "Super + Space|toggle layout mode"

  "Super + Arrows|focus windows"
  "Super + H J K L|focus left / down / up / right"
  "Super + A|focus parent"

  "Super + Shift + Arrows|move windows"
  "Super + Shift + H J K L|move left / down / up / right"

  "Super + S|stacking layout"
  "Super + W|tabbed layout"
  "Super + E|toggle split"

  "Super + R|enter resize mode"
  "J / Left|shrink width"
  "K / Down|grow height"
  "L / Up|shrink height"
  "; / Right|grow width"
  "Enter / Escape / Super + R|leave resize mode"

  "Super + -|show scratchpad"
  "Super + Shift + -|move to scratchpad"

  "Super + 1 2 3 4 5 6 7 8 9 0|switch workspace"
  "Super + Shift + 1 2 3 4 5 6 7 8 9 0|move container to workspace"

  "Alt + F6|volume -5"
  "Alt + F7|volume +5"
  "Alt + F8|mute"
  "Alt + F9|brightness -2"
  "Alt + F10|brightness +2"
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
