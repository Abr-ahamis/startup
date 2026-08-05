#!/usr/bin/env bash
# Optional user-level tool. Missing pipx never aborts the desktop setup.

if [[ -n "${__SETUP_PIPX_LOADED:-}" ]]; then return 0; fi
__SETUP_PIPX_LOADED=1

run_pipx() {
  section_setup "Optional autotiling"
  local autotiling_venv="$TARGET_HOME/.local/share/pipx/venvs/autotiling/bin/autotiling"

  # Prefer the native package when the current distribution provides it.  This
  # gives the target user a normal `autotiling` command in every new shell.
  if package_available autotiling; then
    if ! package_installed autotiling; then
      install_packages autotiling >>"$SETUP_LOG_FILE" 2>&1 || true
    fi
    if package_installed autotiling && run_as_target bash -lc 'command -v autotiling >/dev/null 2>&1'; then
      ok "autotiling is already installed"
      return 0
    fi
  fi

  if [[ "$DISTRO_FAMILY" == "debian" ]]; then
    if ! command -v pipx >/dev/null 2>&1; then
      info "Installing pipx with apt for Debian/Kali/Ubuntu"
      run_as_root apt update >>"$SETUP_LOG_FILE" 2>&1 || warn "apt update failed while preparing pipx"
      run_as_root apt install -y pipx >>"$SETUP_LOG_FILE" 2>&1 || warn "pipx installation via apt failed"
    fi

    if command -v pipx >/dev/null 2>&1; then
      run_as_target pipx ensurepath >/dev/null 2>&1 || true
    fi
  fi

  if ! command -v pipx >/dev/null 2>&1; then warn "pipx is unavailable; autotiling was skipped."; return 0; fi
  if run_as_target pipx list --short 2>/dev/null | awk '{print $1}' | grep -qx autotiling; then
    if [[ -x "$autotiling_venv" && ! -x "$TARGET_HOME/.local/bin/autotiling" ]]; then
      run_as_target mkdir -p "$TARGET_HOME/.local/bin" || true
      run_as_target ln -sfn "$autotiling_venv" "$TARGET_HOME/.local/bin/autotiling" || true
    fi
    if [[ -x "$TARGET_HOME/.local/bin/autotiling" || -x "$autotiling_venv" ]] || run_as_target bash -lc 'PATH="$HOME/.local/bin:$PATH"; command -v autotiling >/dev/null 2>&1'; then
      ok "autotiling is already installed"
      return 0
    fi
    info "autotiling is registered with pipx but its launcher is missing; repairing it."
  fi
  if run_as_target env PATH="$TARGET_HOME/.local/bin:$PATH" pipx install autotiling >>"$SETUP_LOG_FILE" 2>&1 || run_as_target env PATH="$TARGET_HOME/.local/bin:$PATH" pipx reinstall autotiling >>"$SETUP_LOG_FILE" 2>&1; then
    if [[ -x "$autotiling_venv" && ! -x "$TARGET_HOME/.local/bin/autotiling" ]]; then
      run_as_target mkdir -p "$TARGET_HOME/.local/bin" || true
      run_as_target ln -sfn "$autotiling_venv" "$TARGET_HOME/.local/bin/autotiling" || true
    fi
    if [[ -x "$TARGET_HOME/.local/bin/autotiling" || -x "$autotiling_venv" ]]; then
      ok "autotiling installed"
    else
      warn "autotiling installation completed but no executable was found."
    fi
  else
    warn "autotiling could not be installed; Sway will continue without it."
  fi
}
