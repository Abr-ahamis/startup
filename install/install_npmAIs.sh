#!/usr/bin/env bash
# Install/update npm and selected AI command-line clients for the target user.
set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
optional_detect || exit 1
optional_refresh || true

if ! command -v npm >/dev/null 2>&1; then
  echo 'npm is not installed; installing Node.js and npm...'
  optional_install nodejs npm || { echo 'Unable to install Node.js/npm.' >&2; exit 1; }
fi
command -v npm >/dev/null 2>&1 || { echo 'npm is still unavailable after installation.' >&2; exit 1; }

prefix="$target_home/.local"
run_as_target mkdir -p "$prefix/bin" || { echo "Cannot create $prefix/bin" >&2; exit 1; }
export PATH="$prefix/bin:$PATH"

npm_target() {
  run_as_target env NPM_CONFIG_PREFIX="$prefix" PATH="$prefix/bin:$PATH" npm "$@"
}

echo "Updating npm for $target_user..."
if npm_target install --global npm@latest >/dev/null 2>&1; then
  echo "npm updated: $(run_as_target env NPM_CONFIG_PREFIX="$prefix" PATH="$prefix/bin:$PATH" npm --version 2>/dev/null || echo unknown)"
else
  echo 'npm update was not available for this Node.js version; continuing with the installed npm.' >&2
fi

selected=()
while true; do
  printf '\nAI CLI selection\n\n'
  if [[ " ${selected[*]} " == *' 0 '* ]]; then printf '  [x] 1) Codex CLI (@openai/codex)\n'; else printf '  [ ] 1) Codex CLI (@openai/codex)\n'; fi
  if [[ " ${selected[*]} " == *' 1 '* ]]; then printf '  [x] 2) Kilo CLI (@kilocode/cli)\n'; else printf '  [ ] 2) Kilo CLI (@kilocode/cli)\n'; fi
  printf '\nType 1 or 2 to toggle.  f = install/update selected, e = exit.\n'
  read -r -p 'Selection: ' choice || exit 0
  case "${choice,,}" in
    e|exit|q) echo 'AI CLI installation skipped.'; exit 0;;
    f|finish|install)
      ((${#selected[@]} > 0)) || { echo 'No AI CLI selected.' >&2; continue; }
      break
      ;;
    *)
      for token in $choice; do
        case "$token" in
          1) index=0;; 2) index=1;; *) echo "Invalid selection: $token" >&2; continue;;
        esac
        found=0
        for i in "${!selected[@]}"; do
          if [[ "${selected[$i]}" == "$index" ]]; then unset 'selected[i]'; found=1; break; fi
        done
        ((found == 0)) && selected+=("$index")
      done
      selected=("${selected[@]}")
      ;;
  esac
done

for index in "${selected[@]}"; do
  case "$index" in
    0) package='@openai/codex'; command_name=codex; label='Codex CLI';;
    1) package='@kilocode/cli'; command_name=kilo; label='Kilo CLI';;
  esac
  echo "Installing/updating $label..."
  if npm_target install --global "$package@latest"; then
    if run_as_target bash -lc "PATH=\"$prefix/bin:\$PATH\" command -v '$command_name'" >/dev/null 2>&1; then
      echo "$label is ready: $prefix/bin/$command_name"
    else
      echo "$label installed but its command was not found in $prefix/bin." >&2
    fi
  else
    echo "$label installation failed; continuing with the remaining selection." >&2
  fi
done

echo 'npm and selected AI CLI installation finished.'
