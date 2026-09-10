#!/usr/bin/env bash
# Optional creation and privilege assignment for the setup account.

if [[ -n "${__SETUP_USERS_LOADED:-}" ]]; then return 0; fi
__SETUP_USERS_LOADED=1

run_users() {
  section_setup "User account: pro"
  if ! id pro >/dev/null 2>&1; then
    if run_as_root useradd --create-home --shell /bin/bash pro; then
      ok "Created user pro"
    else
      warn "Could not create user pro"
      return 1
    fi
  else
    info "User pro already exists"
  fi

  local admin_group=sudo
  getent group sudo >/dev/null 2>&1 || admin_group=wheel
  if prompt_yes_no "Grant pro administrative privileges through $admin_group?" "n"; then
    if getent group "$admin_group" >/dev/null 2>&1 && run_as_root usermod -aG "$admin_group" pro; then
      ok "pro added to $admin_group"
    else
      warn "Administrative group $admin_group is unavailable"
    fi
  else
    if getent group "$admin_group" >/dev/null 2>&1; then
      run_as_root gpasswd -d pro "$admin_group" >/dev/null 2>&1 || true
    fi
    info "pro remains a non-administrative user"
  fi
}
