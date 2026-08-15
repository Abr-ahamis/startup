#!/usr/bin/env bash
# ==================================================
# 00-common.sh
# Shared helpers: logging, target-user detection,
# privilege helpers, prompts, paths, bright colors.
# ==================================================

if [[ -n "${__SETUP_COMMON_LOADED:-}" ]]; then
  return 0
fi
__SETUP_COMMON_LOADED=1

set -uo pipefail
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a UCF_FORCE_CONFFOLD=1

# ---------- Bright colors (light, like #fc0303) ----------
if [[ -t 1 ]]; then
  SETUP_COLOR_INFO=$'\033[94m'    # bright blue
  SETUP_COLOR_OK=$'\033[92m'      # bright green
  SETUP_COLOR_WARN=$'\033[93m'    # bright yellow
  SETUP_COLOR_ERR=$'\033[91m'     # bright red (#fc0303 style)
  SETUP_COLOR_CYAN=$'\033[96m'    # bright cyan
  SETUP_COLOR_BOLD=$'\033[1m'     # bold
  SETUP_COLOR_DIM=$'\033[2m'      # dim
  SETUP_COLOR_RST=$'\033[0m'      # reset
else
  SETUP_COLOR_INFO=''
  SETUP_COLOR_OK=''
  SETUP_COLOR_WARN=''
  SETUP_COLOR_ERR=''
  SETUP_COLOR_CYAN=''
  SETUP_COLOR_BOLD=''
  SETUP_COLOR_DIM=''
  SETUP_COLOR_RST=''
fi

# ---------- Script paths ----------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_NAME="$(basename -- "${BASH_SOURCE[0]}")"

# ---------- Target user ----------
if [[ -n "${STARTUP_TARGET_USER:-}" ]]; then
  TARGET_USER="$STARTUP_TARGET_USER"
elif [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
  TARGET_USER="$SUDO_USER"
elif (( EUID != 0 )) && [[ "${USER:-}" != root ]]; then
  TARGET_USER="$USER"
else
  # A direct root invocation has no reliable shell identity.  Prefer the
  # active local login reported by logind; never silently configure /root.
  TARGET_USER="$(loginctl list-users --no-legend 2>/dev/null | awk '$2 != "root" {print $2; exit}')"
  TARGET_USER="${TARGET_USER:-root}"
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || true)"
TARGET_GROUP="$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")"
TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo 0)"

if [[ -z "${TARGET_HOME:-}" || "$TARGET_USER" == root ]]; then
  TARGET_HOME=""
fi

# ---------- Timestamp + paths (private, per target user) ----------
SETUP_TIMESTAMP="$(date +'%Y-%m-%d+%H:%M:%S')"
SETUP_BASE_DIR="${SETUP_BASE_DIR:-/tmp/startup-setup-$TARGET_UID}"
SETUP_LOG_DIR="$SETUP_BASE_DIR/log"
SETUP_LOG_FILE="$SETUP_LOG_DIR/setup-$SETUP_TIMESTAMP.log"
SETUP_TRANSCRIPT_FILE="$SETUP_LOG_DIR/transcript-$SETUP_TIMESTAMP.log"
SETUP_RUNTIME_DIR="$SETUP_BASE_DIR/runtime-$SETUP_TIMESTAMP"
SETUP_STARTED_AT="$(date +%s)"
SETUP_ACTIVE_PID=""
SETUP_ACTIVE_PID_FILE="$SETUP_BASE_DIR/active-package.pid"
SETUP_CLEANUP_DONE=0
SETUP_STAGE_CURRENT=0
SETUP_STAGE_TOTAL=9
SETUP_PROGRESS_COMPLETED_WEIGHT=0
SETUP_PROGRESS_ACTIVE_WEIGHT=0
SETUP_PROGRESS_TOTAL_WEIGHT=1
SETUP_ISSUES=()
SETUP_DEFERRED=()
SETUP_COMMAND_SEQUENCE=0
SETUP_FINAL_SWAY_LAUNCHED=0
SETUP_RELOGIN_REQUIRED=0

# ---------- Logging (silent — goes to log file only) ----------
_setup_log_write() {
  local level="$1"
  local msg="$2"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  if [[ -d "$SETUP_LOG_DIR" ]]; then
    printf '%s [%s] %s\n' "$ts" "$level" "$msg" >> "$SETUP_LOG_FILE" 2>/dev/null || true
  fi
}

log_command() {
  local label="$1"; shift
  SETUP_COMMAND_SEQUENCE=$((SETUP_COMMAND_SEQUENCE + 1))
  _setup_log_write COMMAND "#$SETUP_COMMAND_SEQUENCE $label: $(printf '%q ' "$@")"
  "$@"
  local rc=$?
  _setup_log_write COMMAND "#$SETUP_COMMAND_SEQUENCE $label: exit $rc"
  return "$rc"
}

_setup_init_log() {
  mkdir -p -m 700 "$SETUP_LOG_DIR" 2>/dev/null || true
  mkdir -p -m 700 "$SETUP_RUNTIME_DIR" 2>/dev/null || true
}

start_transcript_logging() {
  command -v tee >/dev/null 2>&1 || {
    warn "tee is unavailable; console output will not be mirrored to a transcript."
    return 0
  }
  touch "$SETUP_TRANSCRIPT_FILE" 2>/dev/null || {
    warn "Could not create transcript log: $SETUP_TRANSCRIPT_FILE"
    return 1
  }
  chmod 600 "$SETUP_TRANSCRIPT_FILE" 2>/dev/null || true
  # Preserve the normal terminal output while recording every subsequent
  # stdout/stderr line, including output from optional installer scripts.
  exec > >(tee -a "$SETUP_TRANSCRIPT_FILE") 2>&1
}

elapsed_time() {
  local seconds=$(( $(date +%s) - SETUP_STARTED_AT ))
  printf '%02dm%02ds' "$((seconds / 60))" "$((seconds % 60))"
}

stage() {
  local name="$1" weight="${2:-1}" percent
  # A stage's weight is credited only when the next stage begins. This keeps
  # the displayed percentage tied to completed work, rather than elapsed time.
  SETUP_PROGRESS_COMPLETED_WEIGHT=$((SETUP_PROGRESS_COMPLETED_WEIGHT + SETUP_PROGRESS_ACTIVE_WEIGHT))
  SETUP_PROGRESS_ACTIVE_WEIGHT="$weight"
  SETUP_STAGE_CURRENT=$((SETUP_STAGE_CURRENT + 1))
  percent=$((SETUP_PROGRESS_COMPLETED_WEIGHT * 100 / SETUP_PROGRESS_TOTAL_WEIGHT))
  _setup_log_write STAGE "$SETUP_STAGE_CURRENT/$SETUP_STAGE_TOTAL $name"
}

finish_stage_progress() {
  local percent
  SETUP_PROGRESS_COMPLETED_WEIGHT=$((SETUP_PROGRESS_COMPLETED_WEIGHT + SETUP_PROGRESS_ACTIVE_WEIGHT))
  SETUP_PROGRESS_ACTIVE_WEIGHT=0
  percent=$((SETUP_PROGRESS_COMPLETED_WEIGHT * 100 / SETUP_PROGRESS_TOTAL_WEIGHT))
  (( percent > 100 )) && percent=100
  _setup_log_write PROGRESS "100% required installation stages finished (calculated=$percent%)"
}

terminate_process_tree() {
  local pid="$1" child children
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  children="$(pgrep -P "$pid" 2>/dev/null || true)"
  for child in $children; do terminate_process_tree "$child"; done
  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
}

cleanup_previous_package_process() {
  local pid
  [[ -r "$SETUP_ACTIVE_PID_FILE" ]] || return 0
  pid="$(<"$SETUP_ACTIVE_PID_FILE")"
  [[ "$pid" =~ ^[0-9]+$ ]] || { rm -f -- "$SETUP_ACTIVE_PID_FILE"; return 0; }
  if kill -0 "$pid" 2>/dev/null; then
    warn "Stopping an unfinished package command from a previous setup run (PID $pid)."
    terminate_process_tree "$pid"
    sleep 1
    kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
  fi
  rm -f -- "$SETUP_ACTIVE_PID_FILE"
}

setup_cleanup() {
  local rc="${1:-0}"
  (( SETUP_CLEANUP_DONE == 0 )) || return 0
  SETUP_CLEANUP_DONE=1
  if [[ -n "$SETUP_ACTIVE_PID" ]]; then
    terminate_process_tree "$SETUP_ACTIVE_PID"
    SETUP_ACTIVE_PID=""
  fi
  rm -f -- "$SETUP_ACTIVE_PID_FILE" 2>/dev/null || true
  [[ -d "$SETUP_RUNTIME_DIR" ]] && rm -rf -- "$SETUP_RUNTIME_DIR" 2>/dev/null || true
  # Never launch a compositor from installer cleanup.  Cleanup must be
  # side-effect free with respect to the user's existing desktop session;
  # starting Sway here leaves a child process attached to the terminal.
  _setup_log_write INFO "Cleanup completed (exit $rc, elapsed $(elapsed_time))"
}

setup_interrupted() {
  local signal="$1" rc="$2"
  printf '\n%s[STOP]%s Interrupted by %s; stopping child processes and cleaning up.\n' "$SETUP_COLOR_WARN" "$SETUP_COLOR_RST" "$signal" >&2
  setup_cleanup "$rc"
  exit "$rc"
}

# Long-running commands write their detailed output to the log while a compact
# live status line keeps interactive sessions responsive.  The PID is tracked
# so Ctrl+C can terminate package managers and their children as well.
run_logged() {
  local label="$1"; shift
  local spin='|/-\\' i=0 pid rc
  "$@" >>"$SETUP_LOG_FILE" 2>&1 &
  pid=$!
  SETUP_ACTIVE_PID="$pid"
  while kill -0 "$pid" 2>/dev/null; do
    if [[ -t 1 ]]; then
      printf '\r%s[WORK]%s %s %s elapsed %s' "$SETUP_COLOR_INFO" "$SETUP_COLOR_RST" "${spin:i++%4:1}" "$label" "$(elapsed_time)"
    fi
    sleep 0.2
  done
  wait "$pid"; rc=$?
  SETUP_ACTIVE_PID=""
  [[ -t 1 ]] && printf '\r\033[2K'
  return "$rc"
}

# ---------- Print helpers ----------
info() {
  local msg="$*"
  printf '%s[INFO]%s %s\n' "$SETUP_COLOR_INFO" "$SETUP_COLOR_RST" "$msg"
  _setup_log_write INFO "$msg"
}

ok() {
  local msg="$*"
  printf '%s[ OK ]%s %s\n' "$SETUP_COLOR_OK" "$SETUP_COLOR_RST" "$msg"
  _setup_log_write OK "$msg"
}

warn() {
  local msg="$*"
  printf '%s[WARN]%s %s\n' "$SETUP_COLOR_WARN" "$SETUP_COLOR_RST" "$msg" >&2
  _setup_log_write WARN "$msg"
  SETUP_ISSUES+=("[WARN] $msg")
}

# A deferred desktop-only action is neither a successful operation nor an
# installer failure: it is reported in the final result without being promoted
# to an unresolved error on headless/non-interactive installations.
defer() {
  local msg="$*"
  printf '%s[INFO]%s Deferred: %s\n' "$SETUP_COLOR_INFO" "$SETUP_COLOR_RST" "$msg"
  _setup_log_write DEFERRED "$msg"
  SETUP_DEFERRED+=("$msg")
}

error() {
  local msg="$*"
  printf '%s[FAIL]%s %s\n' "$SETUP_COLOR_ERR" "$SETUP_COLOR_RST" "$msg" >&2
  _setup_log_write ERROR "$msg"
  SETUP_ISSUES+=("[FAIL] $msg")
}

# Section separators
main_sep() {
  local width="${1:-60}"
  local line=""
  local i
  for ((i = 0; i < width; i++)); do line+='─'; done
  printf '%s%s%s\n' "$SETUP_COLOR_CYAN" "$line" "$SETUP_COLOR_RST"
}
sub_sep() {
  local width="${1:-60}"
  local line=""
  local i
  for ((i = 0; i < width; i++)); do line+='─'; done
  printf '%s%s%s\n' "$SETUP_COLOR_CYAN" "$line" "$SETUP_COLOR_RST"
}

# Colored heavy separator (bright cyan)
setup_sep() {
  local width="${1:-60}"
  local line=""
  local i
  for ((i = 0; i < width; i++)); do line+='─'; done
  printf '%s%s%s\n' "$SETUP_COLOR_CYAN" "$line" "$SETUP_COLOR_RST"
}

# Double-line separator (for security banner)
setup_double_sep() {
  local width="${1:-64}"
  local line=""
  local i
  for ((i = 0; i < width; i++)); do line+='═'; done
  printf '%s%s%s\n' "$SETUP_COLOR_CYAN" "$line" "$SETUP_COLOR_RST"
}

section() {
  main_sep
  printf '%s\n' "$1"
  _setup_log_write SECTION "$1"
}

section_setup() {
  main_sep
  printf '%s%s%s\n' "$SETUP_COLOR_BOLD" "$1" "$SETUP_COLOR_RST"
  _setup_log_write SECTION "$1"
}

timestamp() { date +"%Y-%m-%d+%H:%M:%S"; }

# ---------- Progress bar ----------
progress_bar() {
  local percent="$1"
  local filled=$((percent / 10))
  local empty=$((10 - filled))
  local bar=""
  local i
  for ((i = 0; i < filled; i++)); do bar+='█'; done
  for ((i = 0; i < empty; i++)); do bar+='░'; done
  printf '%s%s%s %d%%' "$SETUP_COLOR_CYAN" "$bar" "$SETUP_COLOR_RST" "$percent"
}

progress_stage_complete() {
  local completed="$1" total="$2" label="$3"
  (( total > 0 )) || total=1
  local percent=$(( completed * 100 / total ))
  progress_bar "$percent"
  printf ' %d/%d %s\n' "$completed" "$total" "$label"
  _setup_log_write PROGRESS "$completed/$total ($percent%) $label"
}

# ---------- Privilege helpers ----------
run_as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    if ! command -v sudo >/dev/null 2>&1; then
      error "sudo is required but not installed"
      exit 1
    fi
    sudo "$@"
  fi
}

run_as_target() {
  if [[ "$(id -un)" == "$TARGET_USER" ]]; then
    "$@"
  elif (( EUID == 0 )); then
    if command -v runuser >/dev/null 2>&1; then
      runuser -u "$TARGET_USER" -- "$@"
    elif command -v su >/dev/null 2>&1; then
      su - "$TARGET_USER" -c "$(printf '%q ' "$@")"
    else
      error "runuser/su is required to switch to target user"
      exit 1
    fi
  else
    if ! command -v sudo >/dev/null 2>&1; then
      error "sudo is required but not installed"
      exit 1
    fi
    sudo -u "$TARGET_USER" -H "$@"
  fi
}

target_runtime_dir() {
  printf '/run/user/%s\n' "$TARGET_UID"
}

target_session_available() {
  local runtime
  runtime="$(target_runtime_dir)"
  [[ -d "$runtime" && -S "$runtime/bus" ]]
}

target_wayland_display() {
  local runtime candidate
  runtime="$(target_runtime_dir)"
  if [[ -n "${WAYLAND_DISPLAY:-}" && -S "$runtime/${WAYLAND_DISPLAY##*/}" ]]; then
    printf '%s\n' "${WAYLAND_DISPLAY##*/}"
    return 0
  fi
  candidate="$(find "$runtime" -maxdepth 1 -type s -name 'wayland-*' -printf '%T@ %f\n' 2>/dev/null | sort -nr | awk 'NR == 1 { print $2 }')"
  [[ -n "$candidate" ]] && printf '%s\n' "$candidate"
}

target_sway_socket() {
  local runtime socket
  runtime="$(target_runtime_dir)"
  for socket in "$runtime"/sway-ipc."$TARGET_UID".*.sock; do
    [[ -S "$socket" ]] || continue
    if run_as_target env "XDG_RUNTIME_DIR=$runtime" "SWAYSOCK=$socket" swaymsg -t get_version >/dev/null 2>&1; then
      printf '%s\n' "$socket"
      return 0
    fi
  done
  return 1
}

# Execute against the target user's existing systemd/D-Bus session.  This is
# required when the installer itself is launched through sudo: root's user bus
# is not the desktop user's bus.
run_as_target_session() {
  local runtime wayland_display sway_socket desktop
  local -a session_env
  runtime="$(target_runtime_dir)"
  target_session_available || return 1
  session_env=(env \
    "HOME=$TARGET_HOME" "USER=$TARGET_USER" "LOGNAME=$TARGET_USER" \
    "XDG_RUNTIME_DIR=$runtime" "DBUS_SESSION_BUS_ADDRESS=unix:path=$runtime/bus")
  wayland_display="$(target_wayland_display || true)"
  [[ -n "$wayland_display" ]] && session_env+=("WAYLAND_DISPLAY=$wayland_display")
  desktop="${XDG_CURRENT_DESKTOP:-}"
  [[ -n "$desktop" ]] && session_env+=("XDG_CURRENT_DESKTOP=$desktop")
  sway_socket="$(target_sway_socket || true)"
  [[ -n "$sway_socket" ]] && session_env+=("SWAYSOCK=$sway_socket")
  run_as_target "${session_env[@]}" "$@"
}

# ---------- Filesystem helpers ----------
require_dir() {
  local path="$1"
  local name="$2"
  if [[ ! -d "$path" ]]; then
    error "$name not found: $path"
    exit 1
  fi
}

require_file() {
  local path="$1"
  local name="$2"
  if [[ ! -f "$path" ]]; then
    error "$name not found: $path"
    exit 1
  fi
}

ensure_directory() {
  local path="${1:-}" mode="${2:-755}" owner="${3:-$TARGET_USER:$TARGET_GROUP}"
  if [[ -z "$path" ]]; then warn "ensure_directory called without a path"; return 1; fi
  if ! run_as_root install -d -m "$mode" "$path"; then warn "Could not create directory: $path"; return 1; fi
  run_as_root chown "$owner" "$path" || warn "Could not set owner on directory: $path"
}

fix_tree_permissions() {
  local path="${1:-}" file_mode="${2:-644}"
  [[ -d "$path" ]] || { warn "Cannot set permissions; directory is missing: $path"; return 1; }
  run_as_root find "$path" -type d -exec chmod 755 {} + || warn "Could not set directory permissions under $path"
  run_as_root find "$path" -type f -exec chmod "$file_mode" {} + || warn "Could not set file permissions under $path"
  run_as_root find "$path" -type f -name '*.sh' -exec chmod 755 {} + || warn "Could not set script permissions under $path"
}

fix_project_script_permissions() {
  local root="${1:-$SCRIPT_DIR}"
  [[ -d "$root" ]] || { warn "Cannot fix project permissions; directory is missing: $root"; return 1; }
  run_as_root find "$root" -type f -name '*.sh' -exec chmod 755 {} + || warn "Could not set executable bits on all project scripts"
}

backup_if_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    cp -a "$path" "$path.bak.$(timestamp)"
  fi
}

show_fs_debug() {
  warn "Current folder contents:"
  ls -la "$SCRIPT_DIR" || true
  warn "Subfolders:"
  find "$SCRIPT_DIR" -maxdepth 2 -type d | sort || true
}

# ---------- Session detection ----------
current_uid="$(id -u)"
current_euid="${EUID:-$current_uid}"

can_manage_user_session=false
if target_session_available; then
  can_manage_user_session=true
fi
_setup_log_write INFO "Execution identity: euid=$current_euid target_user=$TARGET_USER target_uid=$TARGET_UID target_home=$TARGET_HOME"
_setup_log_write INFO "Target user session available: $can_manage_user_session (runtime=$(target_runtime_dir))"
_setup_log_write INFO "Detected target Wayland display: $(target_wayland_display || printf 'none')"

# ---------- Interactive prompt ----------
prompt_yes_no() {
  local prompt="$1"
  local default="${2:-none}"
  local hint=""

  if [[ ! -t 0 ]]; then
    warn "$prompt (no interactive terminal; using default)"
    [[ "$default" =~ ^(y|Y|yes)$ ]]
    return
  fi

  case "$default" in
    y|Y|yes) hint="[Y/n]";;
    n|N|no)  hint="[y/N]";;
    *)       hint="[y/n]";;
  esac

  local reply
  read -r -p "$prompt $hint " reply || return 1
  reply="${reply,,}"

  if [[ -z "$reply" ]]; then
    case "$default" in
      y|Y|yes) return 0;;
      n|N|no)  return 1;;
      *)       return 1;;
    esac
  fi

  case "$reply" in
    y|yes) return 0;;
    *)     return 1;;
  esac
}

prompt_yes_no_timeout() {
  local prompt="$1" seconds="${2:-3}" reply
  [[ -t 0 && -t 1 ]] || return 1
  printf '%s [Y/n] (starts in %ss): ' "$prompt" "$seconds"
  if ! read -r -t "$seconds" reply; then
    printf '\n'
    return 0
  fi
  case "${reply,,}" in n|no) return 1;; *) return 0;; esac
}

# Initialize log
_setup_init_log
trap 'setup_interrupted INT 130' INT
trap 'setup_interrupted TERM 143' TERM
trap 'setup_interrupted HUP 129' HUP
trap 'setup_cleanup $?' EXIT
