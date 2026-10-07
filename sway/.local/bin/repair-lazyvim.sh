#!/usr/bin/env bash
# Recover incomplete LazyVim plugin checkouts without replacing user config.
set -uo pipefail

nvim_bin="$(command -v nvim 2>/dev/null || true)"
git_bin="$(command -v git 2>/dev/null || true)"
[[ -n "$nvim_bin" ]] || { echo 'Neovim is not installed.' >&2; exit 127; }
[[ -n "$git_bin" ]] || { echo 'Git is required to repair LazyVim plugins.' >&2; exit 127; }

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
plugin_dir="$data_home/nvim/lazy"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
[[ -d "$config_dir/lua/config" ]] || {
  printf 'No Neovim configuration found at %s. Run setup-neovim.sh first.\n' "$config_dir" >&2
  exit 1
}

if command -v pgrep >/dev/null 2>&1 && pgrep -u "$(id -u)" -x nvim >/dev/null 2>&1; then
  echo 'Close all Neovim sessions before repairing plugin checkouts.' >&2
  exit 1
fi

if ! "$git_bin" ls-remote https://github.com/LazyVim/LazyVim HEAD >/dev/null 2>&1; then
  echo 'Cannot reach GitHub. Check the network/DNS connection, then run this repair script again.' >&2
  exit 1
fi

if [[ ! -d "$plugin_dir" ]]; then
  printf 'Lazy plugin directory not found: %s\n' "$plugin_dir" >&2
  exit 1
fi

failures=0
shopt -s nullglob
for plugin_path in "$plugin_dir"/*/; do
  plugin="${plugin_path%/}"
  [[ -d "$plugin/.git" ]] || continue
  [[ "$($git_bin -C "$plugin" config --bool remote.origin.promisor 2>/dev/null || true)" == true ]] || continue

  status="$($git_bin -C "$plugin" status --porcelain --untracked-files=no 2>/dev/null || true)"
  if [[ -z "$status" ]]; then
    rm -f -- "$plugin.cloning"
    continue
  fi
  if ! awk 'substr($0,1,2) !~ /^(D | D|DD)$/{bad=1} END{exit bad}' <<<"$status"; then
    printf 'Skipping %s: it has local changes beyond an incomplete checkout.\n' "${plugin##*/}" >&2
    failures=1
    continue
  fi

  printf 'Repairing incomplete plugin checkout: %s\n' "${plugin##*/}"
  if ! "$git_bin" -C "$plugin" restore --source=HEAD --staged --worktree -- :/; then
    printf 'Failed to restore files in %s. Its checkout was left in place.\n' "${plugin##*/}" >&2
    failures=1
    continue
  fi
  if ! "$git_bin" -C "$plugin" diff --quiet --exit-code || ! "$git_bin" -C "$plugin" diff --cached --quiet --exit-code; then
    printf 'Checkout remains incomplete: %s\n' "${plugin##*/}" >&2
    failures=1
    continue
  fi
  rm -f -- "$plugin.cloning"
done

echo 'Restoring LazyVim plugins from lazy-lock.json...'
if ! "$nvim_bin" --headless '+Lazy! restore' +qa; then
  echo 'LazyVim restore did not complete. Review the errors above and retry when GitHub is reachable.' >&2
  exit 1
fi

if (( failures )); then
  echo 'Some incomplete checkouts need attention; see the messages above.' >&2
  exit 1
fi

echo 'LazyVim plugin repair completed. Start Neovim normally to verify.'
