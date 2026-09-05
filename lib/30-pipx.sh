#!/usr/bin/env bash
# Optional user-level tool. Missing pipx never aborts the desktop setup.

if [[ -n "${__SETUP_PIPX_LOADED:-}" ]]; then return 0; fi
__SETUP_PIPX_LOADED=1

run_pipx() {
  local autotiling_venv="$TARGET_HOME/.local/share/pipx/venvs/autotiling/bin/autotiling"

  # Prefer the native package when the current distribution provides it.  This
  # gives the target user a normal `autotiling` command in every new shell.
  if package_available autotiling; then
    if ! package_installed autotiling; then
      install_packages autotiling >>"$SETUP_LOG_FILE" 2>&1 || true
    fi
    if package_installed autotiling && run_as_target bash -lc 'command -v autotiling >/dev/null 2>&1'; then
      return 0
    fi
  fi

  if [[ "$DISTRO_FAMILY" == "debian" ]]; then
    if ! command -v pipx >/dev/null 2>&1; then
      run_as_root apt-get install -y --no-install-recommends pipx >>"$SETUP_LOG_FILE" 2>&1 || return 1
    fi

    if command -v pipx >/dev/null 2>&1; then
      run_as_target pipx ensurepath >/dev/null 2>&1 || true
    fi
  fi

  if ! command -v pipx >/dev/null 2>&1; then _setup_log_write WARN 'pipx is unavailable; autotiling could not be configured.'; return 1; fi
  if run_as_target pipx list --short 2>/dev/null | awk '{print $1}' | grep -qx autotiling; then
    if [[ -x "$autotiling_venv" && ! -x "$TARGET_HOME/.local/bin/autotiling" ]]; then
      run_as_target mkdir -p "$TARGET_HOME/.local/bin" || true
      run_as_target ln -sfn "$autotiling_venv" "$TARGET_HOME/.local/bin/autotiling" || true
    fi
    if [[ -x "$TARGET_HOME/.local/bin/autotiling" || -x "$autotiling_venv" ]] || run_as_target bash -lc 'PATH="$HOME/.local/bin:$PATH"; command -v autotiling >/dev/null 2>&1'; then
      return 0
    fi
    _setup_log_write INFO 'Repairing the autotiling launcher.'
  fi
  if run_as_target env PATH="$TARGET_HOME/.local/bin:$PATH" pipx install autotiling >>"$SETUP_LOG_FILE" 2>&1 || run_as_target env PATH="$TARGET_HOME/.local/bin:$PATH" pipx reinstall autotiling >>"$SETUP_LOG_FILE" 2>&1; then
    if [[ -x "$autotiling_venv" && ! -x "$TARGET_HOME/.local/bin/autotiling" ]]; then
      run_as_target mkdir -p "$TARGET_HOME/.local/bin" || true
      run_as_target ln -sfn "$autotiling_venv" "$TARGET_HOME/.local/bin/autotiling" || true
    fi
    if [[ -x "$TARGET_HOME/.local/bin/autotiling" || -x "$autotiling_venv" ]]; then
      return 0
    else
      return 1
    fi
  else
    _setup_log_write WARN 'autotiling could not be installed.'
    return 1
  fi
}
