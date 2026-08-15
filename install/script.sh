#!/usr/bin/env bash
# Standalone optional-installer selector.
set -uo pipefail

installer_interrupted() {
  printf '\n[%s] Installation interrupted. No further changes were made.\n' "$(date +%H:%M:%S)" >&2
  exit 130
}
trap installer_interrupted INT TERM HUP

INSTALL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

scan_installers() {
  scripts=()
  local manifest="$INSTALL_DIR/.startup-installers.$$" file
  find "$INSTALL_DIR" -maxdepth 1 -type f -name 'install_*.sh' -print0 | sort -z >"$manifest" || return 1
  while IFS= read -r -d '' file; do scripts+=("$file"); done <"$manifest"
  rm -f -- "$manifest"
}

run_script() {
  local file="$1"
  printf '\n==============================\nRunning: %s\n==============================\n' "$(basename "$file")"
  chmod +x "$file" 2>/dev/null || true
  local log_file="${STARTUP_LOG_FILE:-/var/log/startup-install.log}"
  if ! touch "$log_file" 2>/dev/null; then log_file="${TMPDIR:-/tmp}/startup-install.log"; touch "$log_file"; fi
  if STARTUP_LOG_FILE="$log_file" bash "$file" >>"$log_file" 2>&1; then
    echo "Finished: $(basename "$file")"
  else
    local rc=$?
    (( rc == 130 || rc == 143 || rc == 129 )) && exit "$rc"
    echo "Failed: $(basename "$file") — see $log_file; continuing with remaining scripts." >&2
  fi
}

scan_installers
if ((${#scripts[@]} == 0)); then
  echo "No install_*.sh scripts found in $INSTALL_DIR" >&2
  exit 1
fi

selected=()
while true; do
  scan_installers
  echo
  echo 'Optional application installers'
  echo '------------------------------'
  for i in "${!scripts[@]}"; do
    if [[ " ${selected[*]} " == *" $i "* ]]; then printf '[x] %d) %s\n' "$((i + 1))" "$(basename "${scripts[$i]}")"; else printf '[ ] %d) %s\n' "$((i + 1))" "$(basename "${scripts[$i]}")"; fi
  done
  echo
  echo 'Type numbers to toggle, f to install selected, or e to exit.'
  read -r -p 'Selection: ' choice || exit 0
  case "${choice,,}" in
    e|q|exit) exit 0;;
    f|finish|install)
      if ((${#selected[@]} == 0)); then echo 'No installers selected.' >&2; continue; fi
      for i in "${selected[@]}"; do [[ -n "${scripts[$i]:-}" ]] && run_script "${scripts[$i]}"; done
      selected=()
      read -r -p 'Press Enter to return to the installer menu...' _ || true
      ;;
    *)
      for token in $choice; do
        [[ "$token" =~ ^[0-9]+$ ]] || { echo "Invalid selection: $token" >&2; continue; }
        index=$((token - 1))
        ((index >= 0 && index < ${#scripts[@]})) || { echo "Selection out of range: $token" >&2; continue; }
        found=0
        for i in "${!selected[@]}"; do [[ "${selected[$i]}" == "$index" ]] && { unset 'selected[i]'; found=1; break; }; done
        ((found == 0)) && selected+=("$index")
      done
      selected=("${selected[@]}")
      ;;
  esac
done
