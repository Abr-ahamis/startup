#!/usr/bin/env bash
set -u
shopt -s lastpipe

# Dependencies are installed only by main.sh.  Runtime menus never invoke a
# package manager or sudo; report missing tools instead.
for required_command in brightnessctl pactl gammastep; do
  command -v "$required_command" >/dev/null 2>&1 || { echo "Missing $required_command; rerun NEO setup." >&2; exit 127; }
done

selected=0
step_brightness=5
step_volume=5
step_night_light=5
state_dir="${XDG_RUNTIME_DIR:-/tmp}"
[[ -w "$state_dir" ]] || state_dir="/tmp"
night_light_state_file="${state_dir}/vol-brigh-menu-night-light-${UID:-user}"
night_light_enabled_file="${state_dir}/vol-brigh-menu-night-light-enabled-${UID:-user}"
toast_msg=""
toast_timer=0

# =========================
# COLORS
# =========================
# Detect color support
if [[ -t 1 ]] && tput colors >/dev/null 2>&1; then
  ncolors=$(tput colors)
fi
if [[ "${ncolors:-0}" -ge 256 ]]; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_DIM='\033[2m'
  C_HEADER='\033[38;5;39m'      # bright blue
  C_BOX='\033[38;5;59m'         # muted blue-gray
  C_SELECTED='\033[38;5;82m'    # green
  C_UNSELECT='\033[38;5;243m'   # gray
  C_BAR_FILL='\033[38;5;214m'   # orange
  C_BAR_EMPTY='\033[38;5;59m'   # dark gray
  C_VALUE='\033[38;5;223m'      # light pink
  C_HELP='\033[38;5;240m'       # dim gray
  C_TOAST_BG='\033[48;5;236m'   # dark bg
  C_TOAST_FG='\033[38;5;82m'    # green text
  C_ARROW='\033[38;5;226m'      # yellow arrow
else
  C_RESET='' C_BOLD='' C_DIM=''
  C_HEADER='' C_BOX='' C_SELECTED='' C_UNSELECT=''
  C_BAR_FILL='' C_BAR_EMPTY='' C_VALUE='' C_HELP=''
  C_TOAST_BG='' C_TOAST_FG='' C_ARROW=''
fi

# =========================
# CLEAN EXIT
# =========================
cleanup() {
  tput cnorm 2>/dev/null || true
  tput rmcup 2>/dev/null || true
  stty sane 2>/dev/null || true
  printf '%b' "$C_RESET"
}

exit_cleanly() {
  trap - EXIT
  cleanup
  exit "${1:-0}"
}

trap cleanup EXIT
trap 'exit_cleanly 130' INT
trap 'exit_cleanly 143' TERM

# =========================
# TERMINAL SETUP
# =========================
tput smcup 2>/dev/null || true
tput civis 2>/dev/null || true
stty -echo -icanon min 0 time 1 2>/dev/null || true
clear

# =========================
# GET VALUES
# =========================
get_brightness() {
  local cur max pct
  cur=$(brightnessctl g 2>/dev/null || echo 0)
  max=$(brightnessctl m 2>/dev/null || echo 1)

  if [[ "$max" -le 0 ]]; then
    echo 0
    return
  fi

  pct=$(( 100 * cur / max ))
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  echo "$pct"
}

get_volume() {
  local vol
  vol=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | awk -F'/' 'NR==1{gsub(/[^0-9]/,"",$2); print $2; exit}')
  [[ -n "${vol:-}" ]] || vol=0
  (( vol < 0 )) && vol=0
  (( vol > 100 )) && vol=100
  echo "$vol"
}

clamp_pct() {
  local value=$1 min=${2:-0} max=${3:-100}

  [[ "$value" =~ ^[0-9]+$ ]] || value=$min
  (( value < min )) && value=$min
  (( value > max )) && value=$max
  echo "$value"
}

night_light_temp_from_pct() {
  local pct
  pct=$(clamp_pct "$1" 1 100)
  echo $(( 6500 - ((pct - 1) * 4000 / 99) ))
}

get_night_light_pct() {
  local pct
  pct=$(cat "$night_light_state_file" 2>/dev/null || true)
  clamp_pct "${pct:-50}" 1 100
}

is_night_light_on() {
  [[ "$(cat "$night_light_enabled_file" 2>/dev/null || true)" == "1" ]] || pgrep -x gammastep >/dev/null 2>&1
}

run_gammastep() {
  pkill -x gammastep >/dev/null 2>&1 || true
  # The menu supplies the temperature itself. Explicit Wayland mode prevents
  # Gammastep from falling back to GeoClue automatic-location mode.
  nohup gammastep -m wayland "$@" >/dev/null 2>&1 &
  disown "$!" 2>/dev/null || true
}

apply_night_light() {
  local pct temp
  pct=$(clamp_pct "$1" 1 100)
  temp=$(night_light_temp_from_pct "$pct")

  run_gammastep -O "$temp"
  { printf '%s\n' "$pct" > "$night_light_state_file"; } 2>/dev/null || true
  { printf '1\n' > "$night_light_enabled_file"; } 2>/dev/null || true
  toast_msg="Night Light ${pct}% (${temp}K)"
  toast_timer=8
}

disable_night_light() {
  pkill -x gammastep >/dev/null 2>&1 || true
  nohup gammastep -x >/dev/null 2>&1 &
  { printf '0\n' > "$night_light_enabled_file"; } 2>/dev/null || true
  toast_msg="Night Light off"
  toast_timer=8
}

toggle_night_light() {
  if is_night_light_on; then
    disable_night_light
  else
    apply_night_light "$(get_night_light_pct)"
  fi
}

# =========================
# SET VALUES
# =========================
set_brightness_up() {
  "$HOME/.local/bin/brightness-control.sh" set "${step_brightness}%+" >/dev/null 2>&1 || true
  toast_msg="Brightness +${step_brightness}%"
  toast_timer=8
}

set_brightness_down() {
  "$HOME/.local/bin/brightness-control.sh" set "${step_brightness}%-" >/dev/null 2>&1 || true
  toast_msg="Brightness -${step_brightness}%"
  toast_timer=8
}

set_volume_up() {
  pactl set-sink-volume @DEFAULT_SINK@ +"${step_volume}%" >/dev/null 2>&1 || true
  toast_msg="Volume +${step_volume}%"
  toast_timer=8
}

set_volume_down() {
  pactl set-sink-volume @DEFAULT_SINK@ -"${step_volume}%" >/dev/null 2>&1 || true
  toast_msg="Volume -${step_volume}%"
  toast_timer=8
}

set_night_light_up() {
  local pct
  pct=$(get_night_light_pct)
  pct=$(( pct + step_night_light ))
  apply_night_light "$pct"
}

set_night_light_down() {
  local pct
  pct=$(get_night_light_pct)
  pct=$(( pct - step_night_light ))
  apply_night_light "$pct"
}

set_night_light_min() {
  apply_night_light 1
}

set_night_light_max() {
  apply_night_light 100
}

# =========================
# UI HELPERS
# =========================
bar() {
  local value=$1
  local width=${2:-20}
  local filled=$(( value * width / 100 ))
  local empty=$(( width - filled ))
  local i

  printf '%b' "$C_BAR_FILL"
  for ((i = 0; i < filled; i++)); do
    printf '█'
  done
  printf '%b' "$C_BAR_EMPTY"
  for ((i = 0; i < empty; i++)); do
    printf '░'
  done
  printf '%b' "$C_RESET"
}

selected_line() {
  local idx=$1 label=$2
  if [[ $selected -eq $idx ]]; then
    printf "${C_ARROW}▶${C_RESET} ${C_BOLD}${C_SELECTED}%s${C_RESET}\n" "$label"
  else
    printf "  ${C_DIM}${C_UNSELECT}%s${C_RESET}\n" "$label"
  fi
}

selected_inline() {
  local idx=$1 label=$2
  if [[ $selected -eq $idx ]]; then
    printf "${C_ARROW}▶${C_RESET} ${C_BOLD}${C_SELECTED}%s${C_RESET}" "$label"
  else
    printf "  ${C_DIM}${C_UNSELECT}%s${C_RESET}" "$label"
  fi
}

draw_toast() {
  if [[ $toast_timer -gt 0 ]]; then
    local msg_len=${#toast_msg}
    local padding=2
    local total_width=$(( msg_len + padding * 2 ))
    local center_col=$(( (40 - total_width) / 2 ))

    printf '\033[18;%dH' "$((center_col < 0 ? 0 : center_col))"
    printf "${C_TOAST_BG} %b %b${C_RESET}" "$toast_msg" "$(printf '%*s' $((padding-1)) '')"
  fi
}

draw() {
  local br vol night_light_pct night_light_temp night_light_status
  br=$(get_brightness)
  vol=$(get_volume)
  night_light_pct=$(get_night_light_pct)
  night_light_temp=$(night_light_temp_from_pct "$night_light_pct")
  if is_night_light_on; then
    night_light_status="on "
  else
    night_light_status="off"
  fi

  printf '\033[H'

  # Top rounded box
  printf "${C_BOX}╭──────────────────────────────────────╮${C_RESET}\n"
  printf "${C_BOX}│${C_RESET}  ${C_BOLD}${C_HEADER}⚡  CONTROL PANEL${C_RESET}                    ${C_BOX}│${C_RESET}\n"
  printf "${C_BOX}╰──────────────────────────────────────╯${C_RESET}\n"
  printf "\n"

  selected_line 0 "☀  Brightness"
  printf "    %b %b%3d%%${C_RESET}\n\n" "$(bar "$br")" "$C_VALUE" "$br"

  selected_inline 1 "🔊 Volume"
  printf "\n    %b %b%3d%%${C_RESET}\n\n" "$(bar "$vol")" "$C_VALUE" "$vol"
  selected_inline 2 "🌙 Night Light"
  printf "\n    %b %b%3d%%${C_RESET} ${C_DIM}🌙 %s${C_RESET}\n\n" "$(bar "$night_light_pct")" "$C_VALUE" "$night_light_pct" "$night_light_status"

  # Bottom rounded box with help
  printf "${C_BOX}╭──────────────────────────────────────╮${C_RESET}\n"
  printf "${C_BOX}│${C_RESET}${C_HELP}  ↑↓ select   ← decrease   → increase  ${C_BOX}│${C_RESET}\n"
  printf "${C_BOX}│${C_RESET}${C_HELP}  Space night  Home min  End max      ${C_BOX}│${C_RESET}\n"
  printf "${C_BOX}│${C_RESET}${C_HELP}  q quit                              ${C_BOX}│${C_RESET}\n"
  printf "${C_BOX}╰──────────────────────────────────────╯${C_RESET}\n"

  # Draw toast if active
  draw_toast

  # Decrement toast timer
  if [[ $toast_timer -gt 0 ]]; then
    ((toast_timer--))
  fi
}

# =========================
# KEY HANDLING
# =========================
key_action=""

read_key() {
  local key key2 key3 key4
  key_action=""

  IFS= read -rsn1 -t 0.12 key || return 1

  case "$key" in
    $'\003') key_action="quit" ;;
    q|Q) key_action="quit" ;;
    ' '|$'\n'|$'\r') key_action="toggle" ;;
    $'\e')
      IFS= read -rsn1 -t 0.05 key2 || return 1
      [[ "$key2" == "[" ]] || return 1

      IFS= read -rsn1 -t 0.05 key3 || return 1
      case "$key3" in
        A) key_action="up" ;;
        B) key_action="down" ;;
        C) key_action="right" ;;
        D) key_action="left" ;;
        H) key_action="home" ;;
        F) key_action="end" ;;
        1|7)
          IFS= read -rsn1 -t 0.05 key4 || key4=""
          [[ "$key4" == "~" ]] && key_action="home"
          ;;
        4|8)
          IFS= read -rsn1 -t 0.05 key4 || key4=""
          [[ "$key4" == "~" ]] && key_action="end"
          ;;
      esac
      ;;
  esac

  [[ -n "$key_action" ]]
}

handle_action() {
  case "$1" in
    quit)
      exit_cleanly 0
      ;;
    up)
      ((selected--))
      (( selected < 0 )) && selected=2
      ;;
    down)
      ((selected++))
      (( selected > 2 )) && selected=0
      ;;
    right)
      case "$selected" in
        0) set_brightness_up ;;
        1) set_volume_up ;;
        2) set_night_light_up ;;
      esac
      ;;
    left)
      case "$selected" in
        0) set_brightness_down ;;
        1) set_volume_down ;;
        2) set_night_light_down ;;
      esac
      ;;
    home)
      case "$selected" in
        0) "$HOME/.local/bin/brightness-control.sh" set 1% >/dev/null 2>&1 || true ;;
        1) pactl set-sink-volume @DEFAULT_SINK@ 0% >/dev/null 2>&1 || true ;;
        2) set_night_light_min ;;
      esac
      ;;
    end)
      case "$selected" in
        0) "$HOME/.local/bin/brightness-control.sh" set 100% >/dev/null 2>&1 || true ;;
        1) pactl set-sink-volume @DEFAULT_SINK@ 100% >/dev/null 2>&1 || true ;;
        2) set_night_light_max ;;
      esac
      ;;
    toggle)
      [[ $selected -eq 2 ]] && toggle_night_light
      ;;
  esac
}

# =========================
# MAIN LOOP
# =========================
draw

while true; do
  if read_key; then
    handle_action "$key_action"
    draw
  elif [[ $toast_timer -gt 0 ]]; then
    draw
  fi
done
