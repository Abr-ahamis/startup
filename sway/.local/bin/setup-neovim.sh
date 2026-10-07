#!/usr/bin/env bash
# Install a LazyVim-compatible Neovim for this user and seed its starter config.
set -euo pipefail

minimum_version=0.11.2
launch_after_setup=0
if [[ "${1:-}" == --launch ]]; then launch_after_setup=1; elif (( $# )); then echo "Usage: $0 [--launch]" >&2; exit 2; fi
user_home="${HOME:?HOME is required}"
local_bin="$user_home/.local/bin"
opt_dir="$user_home/.local/opt/neovim"
config_dir="$user_home/.config/nvim"
stage=""
stage_config=""
mkdir -p "$local_bin" "$opt_dir" "$user_home/.cache"

cleanup() {
  [[ -z "$stage" ]] || rm -rf -- "$stage"
  [[ -z "$stage_config" ]] || rm -rf -- "$stage_config"
}
trap cleanup EXIT

nvim_version() {
  local binary="$1" first_line
  first_line="$("$binary" --version 2>/dev/null | head -n 1 || true)"
  sed -nE 's/.*v([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' <<<"$first_line"
}

version_meets_minimum() {
  local current="$1"
  [[ -n "$current" ]] && [[ "$(printf '%s\n%s\n' "$minimum_version" "$current" | sort -V | head -n 1)" == "$minimum_version" ]]
}

resolve_nvim() {
  if [[ -x "$local_bin/nvim" ]]; then
    printf '%s\n' "$local_bin/nvim"
  else
    command -v nvim 2>/dev/null || true
  fi
}

current_nvim="$(resolve_nvim)"
current_version=""
[[ -z "$current_nvim" ]] || current_version="$(nvim_version "$current_nvim")"

if ! version_meets_minimum "$current_version"; then
  case "$(uname -m)" in
    x86_64) release_arch=x86_64 ;;
    aarch64|arm64) release_arch=arm64 ;;
    *) printf 'Neovim %s or newer is required for LazyVim; no official AppImage mapping for %s.\n' "$minimum_version" "$(uname -m)" >&2; exit 1 ;;
  esac
  command -v curl >/dev/null 2>&1 || { echo 'curl is required to download the current Neovim build.' >&2; exit 1; }

  stage="$(mktemp -d "$user_home/.cache/startup-neovim.XXXXXX")"
  asset="nvim-linux-${release_arch}.appimage"
  download="$stage/$asset"
  url="https://github.com/neovim/neovim/releases/latest/download/$asset"
  curl --fail --location --retry 2 --connect-timeout 15 --output "$download" "$url"
  chmod 755 "$download"

  selected_path=""
  downloaded_version="$(nvim_version "$download")"
  if version_meets_minimum "$downloaded_version"; then
    selected_path="$opt_dir/nvim-${downloaded_version}-${release_arch}.appimage"
    install -m 755 "$download" "$selected_path"
  else
    # AppImage can run without FUSE by extracting its bundled AppRun tree.
    if (cd "$stage" && "$download" --appimage-extract >/dev/null 2>&1); then
      extracted="$stage/squashfs-root"
      downloaded_version="$(nvim_version "$extracted/AppRun")"
      if version_meets_minimum "$downloaded_version"; then
        selected_path="$opt_dir/nvim-${downloaded_version}-${release_arch}"
        rm -rf -- "$selected_path"
        mv -- "$extracted" "$selected_path"
        selected_path="$selected_path/AppRun"
      fi
    fi
  fi

  if [[ -z "$selected_path" ]]; then
    printf 'Could not run the downloaded Neovim AppImage or it did not meet version %s. Keeping the existing installation unchanged.\n' "$minimum_version" >&2
    exit 1
  fi

  marker="$opt_dir/.managed-by-startup"
  if [[ -e "$local_bin/nvim" || -L "$local_bin/nvim" ]]; then
    link_target="$(readlink "$local_bin/nvim" 2>/dev/null || true)"
    if [[ ! -f "$marker" || "$link_target" != "$opt_dir"/* ]]; then
      backup="$local_bin/nvim.bak.$(date +%Y%m%d-%H%M%S)"
      [[ ! -e "$backup" && ! -L "$backup" ]] || backup="$backup.$RANDOM"
      mv -- "$local_bin/nvim" "$backup"
      printf 'Preserved existing %s as %s\n' "$local_bin/nvim" "$backup"
    fi
  fi
  temp_link="$local_bin/.nvim-link.$$"
  ln -s -- "$selected_path" "$temp_link"
  mv -Tf -- "$temp_link" "$local_bin/nvim"
  printf 'Neovim %s installed under %s\n' "$downloaded_version" "$opt_dir"
  current_nvim="$local_bin/nvim"
  current_version="$(nvim_version "$current_nvim")"
  printf '%s\n' 'managed by startup installer' >"$marker"
fi

if ! version_meets_minimum "$current_version"; then
  printf 'Neovim %s is below the LazyVim minimum %s; starter configuration was not installed.\n' "${current_version:-unknown}" "$minimum_version" >&2
  exit 1
fi

# Preserve any existing Neovim settings and data before cloning the starter.
if [[ -f "$config_dir/lua/config/lazy.lua" ]]; then
  printf 'LazyVim is already configured at %s; leaving it unchanged.\n' "$config_dir"
  (( launch_after_setup == 0 )) || exec "$current_nvim"
  exit 0
fi

command -v git >/dev/null 2>&1 || { echo 'git is required to install the LazyVim starter.' >&2; exit 1; }
config_parent="$(dirname -- "$config_dir")"
mkdir -p "$config_parent"
stage_config="$(mktemp -d "$config_parent/.nvim-lazyvim.XXXXXX")"
git clone --depth=1 https://github.com/LazyVim/starter "$stage_config/nvim"
rm -rf -- "$stage_config/nvim/.git"

timestamp="$(date +%Y%m%d-%H%M%S)"
data_paths=(
  "$config_dir"
  "$user_home/.local/share/nvim"
  "$user_home/.local/state/nvim"
  "$user_home/.cache/nvim"
)
backed_up_paths=() backup_paths=()
for path in "${data_paths[@]}"; do
  [[ -e "$path" || -L "$path" ]] || continue
  backup="$path.bak.$timestamp"
  suffix=0
  while [[ -e "$backup" || -L "$backup" ]]; do
    suffix=$((suffix + 1))
    backup="$path.bak.$timestamp.$suffix"
  done
  if ! mv -- "$path" "$backup"; then
    for ((i=${#backed_up_paths[@]}-1; i>=0; i--)); do
      mv -- "${backup_paths[i]}" "${backed_up_paths[i]}" 2>/dev/null || true
    done
    echo "Could not back up Neovim data at $path; restored earlier paths where possible." >&2
    exit 1
  fi
  backed_up_paths+=("$path")
  backup_paths+=("$backup")
  printf 'Backed up %s to %s\n' "$path" "$backup"
done

if ! mv -- "$stage_config/nvim" "$config_dir"; then
  for ((i=${#backed_up_paths[@]}-1; i>=0; i--)); do
    mv -- "${backup_paths[i]}" "${backed_up_paths[i]}" 2>/dev/null || true
  done
  echo 'Could not activate LazyVim starter; restored previous Neovim data where possible.' >&2
  exit 1
fi
printf 'LazyVim starter installed at %s. Run nvim to install its plugins.\n' "$config_dir"
if (( launch_after_setup )); then
  rm -rf -- "$stage_config"
  stage_config=""
  exec "$current_nvim"
fi
