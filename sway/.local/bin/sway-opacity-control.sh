#!/usr/bin/env bash
set -uo pipefail

config="${SWAY_CONFIG_FILE:-$HOME/.config/sway/config}"
start_marker='# >>> NEO app transparency (managed) >>>'
end_marker='# <<< NEO app transparency (managed) <<<'
action="${1:-}"

get_transparency() {
  [[ -r "$config" ]] || { printf '0\n'; return 0; }
  awk '
    $1 == "set" && $2 == "$neo_app_transparency" && $3 ~ /^[0-9]+$/ { value=$3 }
    /for_window \[all\] opacity set [0-9.]+/ {
      if (match($0, /opacity set [0-9.]+/)) {
        opacity=substr($0, RSTART+11, RLENGTH-11)
        legacy=(1-opacity)*100
        value=sprintf("%.0f", legacy)
      }
    }
    END { if (value == "") value=0; if (value<0) value=0; if (value>95) value=95; print value }
  ' "$config"
}

apply_opacity() {
  local value="$1" opacity id tree
  local -a ids=()
  opacity="$(awk -v transparency="$value" 'BEGIN { printf "%.2f", (100-transparency)/100 }')"
  tree="$(swaymsg -t get_tree 2>/dev/null)" || return 1
  mapfile -t ids < <(jq -r '.. | objects | select(.type? == "con" and .pid != null) | .id' <<<"$tree" 2>/dev/null)
  # It is valid to store the preference before any application windows exist;
  # the watcher will apply it when the first window opens.
  ((${#ids[@]} > 0)) || return 0
  for id in "${ids[@]}"; do
    swaymsg "[con_id=$id] opacity set $opacity" >/dev/null 2>&1 || return 1
  done
}

watch_opacity() {
  local value
  while true; do
    value="$(get_transparency)"
    apply_opacity "$value" || true
    swaymsg -m -t subscribe '["window"]' 2>/dev/null |
      while IFS= read -r _event; do
        value="$(get_transparency)"
        apply_opacity "$value" || true
      done
    sleep 1
  done
}

write_transparency_to_config() {
  local value="$1"
  python3 - "$config" "$start_marker" "$end_marker" "$value" <<'PY'
import os, pathlib, re, stat, sys, tempfile

path = pathlib.Path(sys.argv[1])
begin, end, value = sys.argv[2:]
text = path.read_text()
block = f"{begin}\nset $neo_app_transparency {value}\n{end}"
pattern = re.compile(r"(?m)^" + re.escape(begin) + r"\n.*?^" + re.escape(end) + r"\s*", re.S)
if pattern.search(text):
    text = pattern.sub(block + "\n", text, count=1)
else:
    text = text.rstrip() + "\n\n" + block + "\n"
# Remove older runtime rules. The live compositor is updated with IPC below,
# so the menu never reloads Sway or closes itself.
text = re.sub(r"(?m)^for_window \[all\] opacity set [0-9.]+\s*\n?", "", text)
fd, tmp = tempfile.mkstemp(prefix=".sway-config-transparency.", dir=str(path.parent))
try:
    with os.fdopen(fd, "w") as stream:
        stream.write(text)
    os.chmod(tmp, stat.S_IMODE(path.stat().st_mode))
    os.replace(tmp, path)
except BaseException:
    try:
        os.unlink(tmp)
    except FileNotFoundError:
        pass
    raise
PY
}

case "$action" in
  get)
    get_transparency
    ;;
  set)
    value="${2:-}"
    [[ "$value" =~ ^[0-9]+$ ]] && (( value <= 95 )) || {
      echo 'Transparency must be a whole number from 0 to 95.' >&2
      exit 2
    }
    [[ -f "$config" && ! -L "$config" ]] || { echo "Sway config not found: $config" >&2; exit 1; }
    command -v swaymsg >/dev/null 2>&1 || { echo 'swaymsg is unavailable.' >&2; exit 1; }
    command -v jq >/dev/null 2>&1 || { echo 'jq is unavailable.' >&2; exit 1; }
    swaymsg -t get_version >/dev/null 2>&1 || { echo 'Could not connect to the running Sway session.' >&2; exit 1; }

    write_transparency_to_config "$value" || { echo 'Could not save transparency in the Sway config.' >&2; exit 1; }
    apply_opacity "$value" || { echo 'Could not apply opacity to the open windows.' >&2; exit 1; }

    # Retire the previous hard-coded opacity loop if it was left running.
    old_pids="$(pgrep -u "${UID:-$(id -u)}" -f -- "$HOME/.local/bin/opacity.sh" 2>/dev/null || true)"
    while IFS= read -r pid; do
      [[ -n "$pid" && "$pid" != "$$" ]] || continue
      pkill -TERM -P "$pid" 2>/dev/null || true
      kill "$pid" 2>/dev/null || true
    done <<<"$old_pids"
    if ! pgrep -u "${UID:-$(id -u)}" -f -- 'sway-opacity-control\.sh watch' >/dev/null 2>&1; then
      nohup "$HOME/.local/bin/sway-opacity-control.sh" watch >/dev/null 2>&1 &
      disown "$!" 2>/dev/null || true
    fi
    printf '%s\n' "$value"
    ;;
  watch)
    command -v swaymsg >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || exit 0
    watch_opacity
    ;;
  *)
    echo "Usage: $0 get | set <0-95> | watch" >&2
    exit 2
    ;;
esac
