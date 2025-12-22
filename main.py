#!/usr/bin/env python3
"""
startup_setup_full.py  (FULL FIX - integrated)

Summary of behavior:
 - Detects or clones the "startup" repo.
 - Installs core APT packages non-interactively.
 - Backs up existing configs and copies repo configs into the user's home.
 - Ensures ~/.local/bin exists and is added to PATH in .bashrc.
 - Installs battery-monitor script + user service and runs the exact:
       XDG_RUNTIME_DIR=/run/user/<UID> systemctl --user daemon-reexec
       XDG_RUNTIME_DIR=/run/user/<UID> systemctl --user daemon-reload
       XDG_RUNTIME_DIR=/run/user/<UID> systemctl --user restart battery-monitor.service
   as the target non-root user (best-effort).
 - Makes scripts executable.
 - Refreshes i3 the same way as pressing Win+Shift+R using xdotool (tries multiple DISPLAY/XAUTHORITY combos),
   falls back to i3-msg restart if needed, then waits for i3 to respond before continuing.
 - Does NOT apply any GNOME Terminal theming.
 - Does NOT prompt for GRUB theme (apply_grub_theme exists but is not called automatically).
 - Interactive install menu includes Spotify only as the added app (easy to extend).
 - Provides USER_COMMANDS area for adding arbitrary commands to run (documented inline).

Run:
  sudo python3 startup_setup_full.py
"""
from __future__ import annotations
import os
import sys
import shutil
import subprocess
import datetime
import logging
import time
from pathlib import Path
from typing import List, Optional, Callable, Dict, Any
import pwd

# ----------------------
# CONFIG (edit here)
# ----------------------
REPO_URL = "https://github.com/Abr-ahamis/startup.git"
REPO_DIR_NAME = "startup"

# packages to install first (apt-get)
APT_PACKAGES = [
    "i3-wm", "i3blocks", "rofi", "xdotool", "dex", "acpi", "upower",
    "xfce4-power-manager", "i3lock", "xss-lock", "pulseaudio-utils",
    "brightnessctl", "feh", "picom", "fonts-font-awesome", "git", "rsync",
    "unzip", "curl", "wget", "grub-customizer", "timeshift"
]

# ----------------------
# APP MENU - only add apps here (Spotify only added per your request)
# ----------------------
# To add more apps:
#  1) add an entry here (e.g. 8: "myapp")
#  2) implement install_myapp(startup_dir) below
#  3) add mapping in INSTALL_DISPATCH
APP_OPTIONS = {
    1: "telegram",
    2: "brave-nightly",
    3: "vscode",
    4: "protonvpn",
    5: "virtualbox",
    6: "rustscan",
    7: "spotify",            # <-- Spotify only, per your instruction
}

# ----------------------
# Logging
# ----------------------
logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
log = logging.getLogger("startup_setup")

# ----------------------
# Utilities & environment detection
# ----------------------
def get_target_user() -> str:
    sudo_user = os.environ.get("SUDO_USER")
    if sudo_user:
        return sudo_user
    return os.environ.get("USER", "root")


def get_user_home(user: str) -> Path:
    return Path(pwd.getpwnam(user).pw_dir)


TARGET_USER = get_target_user()
USER_HOME = get_user_home(TARGET_USER)
log.info(f"Target user: {TARGET_USER}, home: {USER_HOME}")

def die(msg: str, code: int = 1):
    log.error(msg)
    sys.exit(code)


def run(cmd, check: bool = False, capture_output: bool = False, env: Optional[dict] = None, shell: bool = False):
    """
    Wrapper around subprocess.run:
      - cmd: list or string
      - check: if True, raise CalledProcessError on non-zero exit
      - capture_output: capture stdout/stderr
      - env: additional env vars
      - shell: if True, run via shell
    """
    if isinstance(cmd, (list, tuple)):
        log.info(f"[CMD] {' '.join(map(str, cmd))}")
    else:
        log.info(f"[CMD] {cmd}")
    try:
        return subprocess.run(cmd, check=check, capture_output=capture_output, text=True, env=env, shell=shell)
    except subprocess.CalledProcessError as e:
        log.warning(f"[CMD-FAIL] returncode={e.returncode} cmd={e.cmd}")
        if capture_output:
            log.warning("stdout: %s", e.stdout)
            log.warning("stderr: %s", e.stderr)
        if check:
            raise
        return e


def ensure_dir(p: Path, mode: int = 0o755):
    if not p.exists():
        log.info(f"[MKDIR] {p}")
        p.mkdir(parents=True, mode=mode, exist_ok=True)


def unique_backup_name(p: Path) -> Path:
    base = p.with_name(p.name + ".backup")
    if not base.exists():
        return base
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    return p.with_name(p.name + f".backup.{ts}")


def backup_existing(dst: Path) -> Optional[Path]:
    try:
        if not dst.exists():
            return None
        b = unique_backup_name(dst)
        log.info(f"[BACKUP] Renaming existing {dst} -> {b}")
        shutil.move(str(dst), str(b))
        return b
    except Exception as e:
        log.warning(f"[WARN] Failed to backup {dst}: {e}")
        return None


def chown_recursive(path: Path, user: str):
    try:
        pw = pwd.getpwnam(user)
        uid, gid = pw.pw_uid, pw.pw_gid
        if path.is_dir():
            for root, dirs, files in os.walk(path):
                os.chown(root, uid, gid)
                for d in dirs:
                    os.chown(os.path.join(root, d), uid, gid)
                for f in files:
                    os.chown(os.path.join(root, f), uid, gid)
        else:
            os.chown(str(path), uid, gid)
    except Exception as e:
        log.warning(f"[WARN] chown failed for {path}: {e}")


def safe_copy(src: Path, dst: Path, make_backup: bool = True, dirs_exist_ok: bool = False) -> bool:
    src = Path(src)
    dst = Path(dst)
    if not src.exists():
        log.info(f"[SKIP] Source not found: {src}")
        return False
    ensure_dir(dst.parent)
    if dst.exists():
        if make_backup:
            backup_existing(dst)
        else:
            if dst.is_dir():
                shutil.rmtree(dst, ignore_errors=True)
            else:
                try:
                    dst.unlink()
                except Exception:
                    pass
    try:
        if src.is_dir():
            log.info(f"[COPY-DIR] {src} -> {dst}")
            shutil.copytree(src, dst, dirs_exist_ok=dirs_exist_ok)
        else:
            log.info(f"[COPY-FILE] {src} -> {dst}")
            shutil.copy2(src, dst)
        try:
            chown_recursive(dst, TARGET_USER)
        except Exception:
            pass
        return True
    except Exception as e:
        log.warning(f"[WARN] Copy failed {src} -> {dst}: {e}")
        return False


# ----------------------
# Root check
# ----------------------
def require_root():
    if os.geteuid() != 0:
        die("This script must be run as root. Use sudo python3 startup_setup_full.py")


# ----------------------
# Repo detection / cloning
# ----------------------
def detect_or_clone_repo() -> Path:
    cwd = Path.cwd()
    log.info(f"Working directory: {cwd}")
    if (cwd / "i3").is_dir() and (cwd / "grub").is_dir() and (cwd / "wallpaper").is_dir():
        log.info("[INFO] Found startup files in current directory; using current dir as startup repo.")
        return cwd
    if (cwd / REPO_DIR_NAME).is_dir():
        log.info(f"[INFO] Found ./{REPO_DIR_NAME}; using it.")
        return cwd / REPO_DIR_NAME
    target = cwd / REPO_DIR_NAME
    if target.exists():
        log.info(f"[INFO] {target} exists; using it.")
        return target
    log.info(f"[INFO] Cloning {REPO_URL} -> {target}")
    r = run(["git", "clone", REPO_URL, str(target)], check=False, capture_output=True)
    if getattr(r, "returncode", 1) != 0:
        log.warning("[WARN] git clone returned non-zero; continuing in case repo exists locally.")
    return target


# ----------------------
# APT package installation
# ----------------------
def install_apt_packages(packages: List[str]):
    if not packages:
        log.info("[APT] No packages to install.")
        return
    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    log.info("[APT] Running apt update...")
    run(["apt", "update"], check=False, env=env)
    cmd = ["apt", "install", "-y"] + packages
    log.info(f"[APT] Installing packages: {len(packages)} items")
    run(cmd, check=False, env=env)


# ----------------------
# Copy core configs (i3, rofi, picom, fonts, scripts, wallpapers)
# ----------------------
def copy_core_configs(startup_dir: Path):
    log.info("[COPY] Copying configs from repo...")
    repo_i3 = startup_dir / "i3"
    # i3 config file
    safe_copy(repo_i3 / ".config" / "i3" / "config", USER_HOME / ".config" / "i3" / "config", make_backup=True)

    # i3 scripts directory
    src_i3_scripts = repo_i3 / ".config" / "i3" / "scripts"
    dst_i3_scripts = USER_HOME / ".config" / "i3" / "scripts"
    if src_i3_scripts.exists() and src_i3_scripts.is_dir():
        ensure_dir(dst_i3_scripts)
        for f in sorted(src_i3_scripts.iterdir()):
            if f.is_file():
                safe_copy(f, dst_i3_scripts / f.name, make_backup=True)
    else:
        log.info(f"[COPY] No i3 scripts directory found in repo at {src_i3_scripts}; skipping.")

    # other configs
    safe_copy(repo_i3 / ".config" / "i3blocks", USER_HOME / ".config" / "i3blocks", make_backup=True, dirs_exist_ok=True)
    safe_copy(repo_i3 / ".config" / "rofi", USER_HOME / ".config" / "rofi", make_backup=True, dirs_exist_ok=True)
    safe_copy(repo_i3 / ".config" / "picom" / "picom.conf", USER_HOME / ".config" / "picom" / "picom.conf", make_backup=True)

    # local bin
    src_local_bin = repo_i3 / ".local" / "bin"
    dst_local_bin = USER_HOME / ".local" / "bin"
    ensure_dir(dst_local_bin)
    if src_local_bin.exists():
        for f in sorted(src_local_bin.iterdir()):
            safe_copy(f, dst_local_bin / f.name, make_backup=True)

    # fonts
    src_fonts = repo_i3 / ".local" / "share" / "fonts"
    dst_fonts = USER_HOME / ".local" / "share" / "fonts"
    ensure_dir(dst_fonts)
    if src_fonts.exists():
        for f in sorted(src_fonts.iterdir()):
            safe_copy(f, dst_fonts / f.name, make_backup=True)

    # Ensure ~/.local/bin is present and add to .bashrc if missing
    bashrc = USER_HOME / ".bashrc"
    path_line = 'export PATH="$HOME/.local/bin:$PATH"'
    if bashrc.exists():
        content = bashrc.read_text()
        if path_line not in content:
            log.info("[PATH] Appending PATH line to .bashrc")
            with open(bashrc, "a") as fh:
                fh.write(f"\n{path_line}\n")
        else:
            log.info("[PATH] PATH already present in .bashrc")
    else:
        log.info("[PATH] .bashrc not found, creating one with PATH line.")
        with open(bashrc, "w") as fh:
            fh.write(f"{path_line}\n")
    os.environ["PATH"] = str(USER_HOME / ".local" / "bin") + ":" + os.environ.get("PATH", "")

    # wallpapers
    repo_wall = startup_dir / "wallpaper"
    ensure_dir(USER_HOME / "Pictures")
    for name in ("wallpaper.jpg", "wallpaper-1.jpg", "wallpaper-2.jpg"):
        s = repo_wall / name
        if s.exists():
            safe_copy(s, USER_HOME / "Pictures" / name, make_backup=True)
            backgrounds_dir = Path("/usr/share/backgrounds/kali")
            ensure_dir(backgrounds_dir)
            try:
                shutil.copy2(s, backgrounds_dir / name)
            except Exception as e:
                log.warning(f"[WARN] copying wallpaper to system backgrounds failed: {e}")


# ----------------------
# Install battery monitor (script + systemd --user service)
# ----------------------
def install_battery_monitor(startup_dir: Path):
    """
    Install battery-monitor script and user systemd service from the repo into the
    target user's home and attempt to enable & start the service using systemctl --user
    sequence as the target user with XDG_RUNTIME_DIR set.
    """
    repo_script = startup_dir / "i3" / ".local" / "bin" / "battery-monitor.sh"
    repo_service = startup_dir / "i3" / ".config" / "systemd" / "user" / "battery-monitor.service"

    dst_script = USER_HOME / ".local" / "bin" / "battery-monitor.sh"
    dst_service = USER_HOME / ".config" / "systemd" / "user" / "battery-monitor.service"

    # Copy script
    if repo_script.exists():
        ensure_dir(dst_script.parent)
        if safe_copy(repo_script, dst_script, make_backup=True):
            try:
                dst_script.chmod(0o755)
            except Exception:
                pass
            try:
                chown_recursive(dst_script, TARGET_USER)
            except Exception:
                pass
            log.info("[BATTERY] Installed battery-monitor script to %s", dst_script)
    else:
        log.info("[BATTERY] No battery-monitor script found in repo (%s). Skipping script install.", repo_script)

    # Copy user service
    if repo_service.exists():
        ensure_dir(dst_service.parent)
        if safe_copy(repo_service, dst_service, make_backup=True):
            try:
                chown_recursive(dst_service, TARGET_USER)
            except Exception:
                pass
            log.info("[BATTERY] Installed battery-monitor user service to %s", dst_service)

            # Ensure DBUS environment line is present in the [Service] section
            try:
                env_line = "Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%U/bus"
                text = dst_service.read_text(encoding="utf-8")
                if env_line not in text:
                    lines = text.splitlines()
                    inserted = False
                    for i, ln in enumerate(lines):
                        if ln.strip() == "[Service]":
                            j = i + 1
                            while j < len(lines) and not lines[j].strip().startswith("["):
                                j += 1
                            lines.insert(j, env_line)
                            inserted = True
                            break
                    if not inserted:
                        if not lines or lines[-1].strip() != "":
                            lines.append("")
                        lines.append(env_line)
                    dst_service.write_text("\n".join(lines) + "\n", encoding="utf-8")
                    try:
                        dst_service.chmod(0o644)
                    except Exception:
                        pass
                    try:
                        chown_recursive(dst_service, TARGET_USER)
                    except Exception:
                        pass
                    log.info("[BATTERY] Injected DBUS Environment line into %s", dst_service)
            except Exception as e:
                log.warning(f"[BATTERY] Could not ensure DBUS env in service file: {e}")
    else:
        log.info("[BATTERY] No battery-monitor.service found in repo (%s). Skipping service install.", repo_service)

    # Now attempt to run the exact command sequence as the target user:
    try:
        pw = pwd.getpwnam(TARGET_USER)
        uid = pw.pw_uid
        runtime_dir = Path(f"/run/user/{uid}")
        if not runtime_dir.exists():
            log.warning("[BATTERY] /run/user/%d does not exist. The target user may not have an active login session; systemctl --user may fail.", uid)
        cmds = [
            f"XDG_RUNTIME_DIR=/run/user/{uid} systemctl --user daemon-reexec",
            f"XDG_RUNTIME_DIR=/run/user/{uid} systemctl --user daemon-reload",
            f"XDG_RUNTIME_DIR=/run/user/{uid} systemctl --user restart battery-monitor.service",
        ]
        log.info("[BATTERY] Running systemctl --user commands as user %s", TARGET_USER)
        for cmd in cmds:
            r = run(["sudo", "-u", TARGET_USER, "bash", "-lc", cmd], check=False, capture_output=True)
            rc = getattr(r, "returncode", 1)
            stdout = getattr(r, "stdout", "") or ""
            stderr = getattr(r, "stderr", "") or ""
            if rc == 0:
                log.info("[BATTERY] Command succeeded: %s", cmd)
                if stdout:
                    log.info("[BATTERY-OUT] %s", stdout.strip())
            else:
                log.warning("[BATTERY] Command returned non-zero (rc=%s): %s", rc, cmd)
                if stdout:
                    log.warning("[BATTERY-OUT] %s", stdout.strip())
                if stderr:
                    log.warning("[BATTERY-ERR] %s", stderr.strip())
        log.info("[BATTERY] systemctl --user sequence attempted.")
    except Exception as e:
        log.warning(f"[BATTERY] Failed to run systemctl --user commands: {e}")
        log.warning("[BATTERY] The service is installed but may need manual enable/start by the user.")


# ----------------------
# i3 detection & refresh helpers
# ----------------------
def is_user_running_i3() -> bool:
    """
    Return True if the target user appears to be running i3.
    Strategy:
      1) Try `pgrep -u <uid> -x i3` (fast, reliable)
      2) Fallback: run `i3-msg -t get_version` as the user with XDG_RUNTIME_DIR set.
    If both checks fail, return False.
    """
    try:
        pw = pwd.getpwnam(TARGET_USER)
        uid = pw.pw_uid
    except Exception:
        log.warning("[I3-CHECK] Could not look up user %s", TARGET_USER)
        return False

    # 1) pgrep check
    try:
        r = run(["pgrep", "-u", str(uid), "-x", "i3"], check=False, capture_output=True)
        if getattr(r, "returncode", 1) == 0:
            log.info("[I3-CHECK] Found i3 process for user %s (pgrep).", TARGET_USER)
            return True
    except Exception:
        pass

    # 2) Fallback: try i3-msg get_version as the user with XDG_RUNTIME_DIR set
    try:
        cmd = f'XDG_RUNTIME_DIR=/run/user/{uid} i3-msg -t get_version'
        r = run(["sudo", "-u", TARGET_USER, "bash", "-lc", cmd], check=False, capture_output=True)
        rc = getattr(r, "returncode", 1)
        out = (getattr(r, "stdout", "") or "").strip()
        if rc == 0 and out:
            log.info("[I3-CHECK] i3 responded to i3-msg for user %s.", TARGET_USER)
            return True
    except Exception:
        pass

    log.info("[I3-CHECK] No i3 session detected for user %s; skipping i3 refresh.", TARGET_USER)
    return False


def try_send_xdotool_refresh(timeout: int = 5) -> bool:
    """
    Attempt to simulate Win+Shift+R in the user's X session using xdotool.
    Returns True if xdotool command ran successfully.
    Tries common DISPLAY values and the user's XAUTHORITY file.
    """
    displays = [":0", ":0.0", ":1"]
    xauth_candidates = [
        str(USER_HOME / ".Xauthority"),
        f"/run/user/{pwd.getpwnam(TARGET_USER).pw_uid}/gdm/Xauthority" if Path(f"/run/user/{pwd.getpwnam(TARGET_USER).pw_uid}/gdm").exists() else "",
    ]
    # xdotool combo: Super (Win) + Shift + r
    key_cmd = "xdotool keydown Super keydown Shift key r keyup Shift keyup Super"

    for disp in displays:
        for xauth in [p for p in xauth_candidates if p]:
            wrapper = f'export DISPLAY="{disp}" && export XAUTHORITY="{xauth}" && {key_cmd}'
            cmd = ["sudo", "-u", TARGET_USER, "bash", "-lc", wrapper]
            log.info("[I3-REFRESH] Trying xdotool on DISPLAY=%s XAUTHORITY=%s", disp, xauth)
            r = run(cmd, check=False, capture_output=True)
            rc = getattr(r, "returncode", 1)
            stdout = getattr(r, "stdout", "") or ""
            stderr = getattr(r, "stderr", "") or ""
            if rc == 0:
                log.info("[I3-REFRESH] xdotool reported success on %s (stdout: %s)", disp, stdout.strip())
                return True
            else:
                log.debug("[I3-REFRESH] xdotool failed on %s (rc=%s). stdout=%s stderr=%s", disp, rc, stdout.strip(), stderr.strip())

    # try without explicit XAUTHORITY (some setups use DISPLAY only)
    for disp in displays:
        wrapper = f'export DISPLAY="{disp}" && {key_cmd}'
        cmd = ["sudo", "-u", TARGET_USER, "bash", "-lc", wrapper]
        log.info("[I3-REFRESH] Trying xdotool on DISPLAY=%s (no XAUTHORITY)", disp)
        r = run(cmd, check=False, capture_output=True)
        rc = getattr(r, "returncode", 1)
        stdout = getattr(r, "stdout", "") or ""
        stderr = getattr(r, "stderr", "") or ""
        if rc == 0:
            log.info("[I3-REFRESH] xdotool reported success on %s (stdout: %s)", disp, stdout.strip())
            return True
        else:
            log.debug("[I3-REFRESH] xdotool failed on %s (rc=%s). stdout=%s stderr=%s", disp, rc, stdout.strip(), stderr.strip())

    log.warning("[I3-REFRESH] xdotool refresh attempts failed (xdotool may be missing or no X session found).")
    return False


def wait_for_i3_ready(timeout: int = 20) -> bool:
    """
    Poll i3 (as target user) until it responds to `i3-msg -t get_version`.
    Returns True if i3 responded within timeout seconds, False otherwise.
    """
    log.info("[I3-WAIT] Waiting for i3 to be ready (timeout %ds)...", timeout)
    start = time.time()
    while time.time() - start < timeout:
        try:
            r = run(["sudo", "-u", TARGET_USER, "bash", "-lc", "i3-msg -t get_version"], check=False, capture_output=True)
            rc = getattr(r, "returncode", 1)
            out = (getattr(r, "stdout", "") or "").strip()
            if rc == 0 and out:
                log.info("[I3-WAIT] i3 responded: %s", out.splitlines()[0] if out else "<empty>")
                return True
        except Exception:
            pass
        time.sleep(1)
    log.warning("[I3-WAIT] i3 did not respond within %d seconds.", timeout)
    return False


# ----------------------
# Make scripts executable and refresh i3 (Win+Shift+R or fallback)
# ----------------------
def set_executables_and_restart_i3():
    """
    Make user scripts executable, then attempt to refresh i3 via xdotool (Win+Shift+R)
    only if the target user is actually running i3. Otherwise skip refresh cleanly.
    Falls back to i3-msg restart if xdotool fails.
    """
    # Ensure scripts are executable (i3blocks, rofi, i3 scripts, local bin)
    scripts_dir = USER_HOME / ".config" / "i3blocks" / "scripts"
    if scripts_dir.exists():
        for sh in scripts_dir.glob("*.sh"):
            log.info(f"[CHMOD] +x {sh}")
            try:
                sh.chmod(0o755)
            except Exception:
                pass

    rofi_dir = USER_HOME / ".config" / "rofi"
    if rofi_dir.exists():
        for f in rofi_dir.rglob("*.sh"):
            log.info(f"[CHMOD] +x {f}")
            try:
                f.chmod(0o755)
            except Exception:
                pass

    i3_scripts_dir = USER_HOME / ".config" / "i3" / "scripts"
    if i3_scripts_dir.exists():
        for f in i3_scripts_dir.iterdir():
            if f.is_file():
                log.info(f"[CHMOD] +x {f}")
                try:
                    f.chmod(0o755)
                except Exception:
                    pass

    local_bin = USER_HOME / ".local" / "bin"
    if local_bin.exists():
        for f in local_bin.iterdir():
            if f.is_file():
                try:
                    f.chmod(0o755)
                except Exception:
                    pass

    # Only attempt refresh if i3 is running for the user
    if not is_user_running_i3():
        log.info("[I3-REFRESH] Target user does not appear to be running i3; skipping refresh step.")
        return

    # 1) Try to refresh via keyboard (xdotool)
    refreshed = False
    try:
        r = run(["which", "xdotool"], check=False, capture_output=True)
        if getattr(r, "returncode", 1) == 0 and (getattr(r, "stdout", "") or "").strip():
            refreshed = try_send_xdotool_refresh()
        else:
            log.info("[I3-REFRESH] xdotool not found on system; skipping keypress method.")
    except Exception as e:
        log.warning("[I3-REFRESH] Exception checking xdotool: %s", e)

    # 2) Fallback: try i3-msg restart as the user (may fail if socket unavailable)
    if not refreshed:
        try:
            log.info("[I3-REFRESH] Falling back to i3-msg restart (best-effort).")
            run(["sudo", "-u", TARGET_USER, "i3-msg", "restart"], check=False, capture_output=True)
        except Exception as e:
            log.warning(f"[WARN] Could not run i3-msg restart: {e}")

    # 3) Wait for i3 to be ready
    i3_ready = wait_for_i3_ready(timeout=20)
    if not i3_ready:
        log.warning("[I3-REFRESH] i3 did not respond after refresh attempts; continuing anyway.")
    else:
        log.info("[I3-REFRESH] i3 reported ready after refresh.")


# ----------------------
# GRUB theme apply (kept but not called automatically)
# ----------------------
def apply_grub_theme(startup_dir: Path):
    log.info("[GRUB] Applying grub theme (best-effort).")
    repo_grub = startup_dir / "grub"
    dst_boot_grub = Path("/boot/grub/themes/kali")
    if dst_boot_grub.exists():
        shutil.rmtree(dst_boot_grub, ignore_errors=True)
    try:
        shutil.copytree(repo_grub, dst_boot_grub)
        log.info(f"[GRUB] Copied {repo_grub} -> {dst_boot_grub}")
    except Exception as e:
        log.warning(f"[WARN] Could not copy grub theme: {e}")
    dst_usr = Path("/usr/share/grub/themes")
    ensure_dir(dst_usr)
    try:
        if (dst_usr / "kali").exists():
            shutil.rmtree(dst_usr / "kali", ignore_errors=True)
        shutil.copytree(dst_boot_grub, dst_usr / "kali", dirs_exist_ok=True)
    except Exception as e:
        log.warning(f"[WARN] Could not copy to {dst_usr}: {e}")


# ----------------------
# App installers (implementations)
# ----------------------
def install_telegram(startup_dir: Optional[Path] = None):
    log.info("[TELEGRAM] Installing Telegram (tarball) — best-effort.")
    tfile = Path("/tmp/tsetup.tar.xz")
    run(["wget", "-q", "https://telegram.org/dl/desktop/linux", "-O", str(tfile)], check=False)
    opt = Path("/opt/Telegram")
    if opt.exists():
        backup_existing(opt)
    ensure_dir(opt)
    run(["tar", "-xf", str(tfile), "-C", str(opt), "--strip-components=1"], check=False)
    tbin = opt / "Telegram"
    if tbin.exists():
        try:
            tbin.chmod(0o755)
        except Exception:
            pass
        ensure_dir(Path("/usr/local/bin"))
        try:
            link = Path("/usr/local/bin/telegram")
            if link.exists() or link.is_symlink():
                try:
                    link.unlink()
                except Exception:
                    pass
            link.symlink_to(tbin)
            log.info(f"[TELEGRAM] Created symlink {link} -> {tbin}")
        except Exception as e:
            log.warning(f"[WARN] Could not create symlink for telegram: {e}")
    else:
        log.warning("[WARN] Telegram binary not found after extraction.")


def install_brave_nightly(startup_dir: Optional[Path] = None):
    log.info("[BRAVE] Installing Brave (nightly) — best-effort.")
    run('curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly bash', check=False, shell=True)
    run(["apt", "install", "-y", "brave-browser-nightly"], check=False)


def install_vscode(startup_dir: Optional[Path] = None):
    log.info("[VSCODE] Installing Visual Studio Code (.deb) — best-effort.")
    deb = Path("/tmp/code.deb")
    run(["wget", "-q", "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64", "-O", str(deb)], check=False)
    if deb.exists():
        r = run(["dpkg", "-i", str(deb)], check=False)
        if getattr(r, "returncode", 0) != 0:
            run(["apt", "install", "-f", "-y"], check=False)
        try:
            deb.unlink()
        except Exception:
            pass


def install_protonvpn(startup_dir: Optional[Path] = None):
    log.info("[PROTONVPN] Installing ProtonVPN repo package (best-effort).")
    deb = Path("/tmp/protonvpn.deb")
    url = "https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb"
    run(["wget", "-q", url, "-O", str(deb)], check=False)
    if deb.exists():
        run(["dpkg", "-i", str(deb)], check=False)
        run(["apt", "update"], check=False)
        run(["apt", "install", "-f", "-y"], check=False)
        run(["apt", "install", "-y", "proton-vpn-gnome-desktop"], check=False)


def install_virtualbox(startup_dir: Optional[Path] = None):
    log.info("[VBOX] Installing VirtualBox (from apt) — best-effort.")
    run(["apt", "update"], check=False)
    run(["apt", "install", "-y", "virtualbox"], check=False)


def install_rustscan(startup_dir: Optional[Path] = None):
    log.info("[RUSTSCAN] Installing RustScan (.deb) — best-effort.")
    deb = Path("/tmp/rustscan_2.2.3_amd64.deb")
    url = "https://github.com/RustScan/RustScan/releases/download/2.2.3/rustscan_2.2.3_amd64.deb"
    run(["wget", "-q", url, "-O", str(deb)], check=False)
    if deb.exists():
        r = run(["dpkg", "-i", str(deb)], check=False)
        if getattr(r, "returncode", 0) != 0:
            run(["apt", "install", "-f", "-y"], check=False)


def install_spotify(startup_dir: Optional[Path] = None):
    """
    Best-effort Spotify installer:
      - Try apt repo + keyring method
      - Fallback to snap if apt fails or snap is preferred
    """
    log.info("[SPOTIFY] Installing Spotify (best-effort).")
    try:
        run(["apt", "update"], check=False)
        run(["bash", "-lc", "curl -sS https://download.spotify.com/debian/pubkey_0D811D58.gpg | gpg --dearmor -o /usr/share/keyrings/spotify-archive-keyring.gpg"], check=False, shell=True)
        list_file = Path("/etc/apt/sources.list.d/spotify.list")
        list_content = "deb [signed-by=/usr/share/keyrings/spotify-archive-keyring.gpg] http://repository.spotify.com stable non-free\n"
        try:
            list_file.write_text(list_content)
            log.info("[SPOTIFY] wrote %s", list_file)
        except Exception as e:
            log.warning("[SPOTIFY] Could not write sources list directly: %s", e)
        run(["apt", "update"], check=False)
        run(["apt", "install", "-y", "spotify-client"], check=False)
        log.info("[SPOTIFY] apt install attempted.")
    except Exception as e:
        log.warning("[SPOTIFY] apt-based install failed: %s", e)
    # fallback to snap
    try:
        run(["snap", "install", "spotify"], check=False)
    except Exception:
        log.info("[SPOTIFY] snap fallback not available or failed; install may require manual steps.")


# dispatch mapping name -> callable
INSTALL_DISPATCH: Dict[str, Callable[[Optional[Path]], None]] = {
    "telegram": install_telegram,
    "brave-nightly": install_brave_nightly,
    "vscode": install_vscode,
    "protonvpn": install_protonvpn,
    "virtualbox": install_virtualbox,
    "rustscan": install_rustscan,
    "spotify": install_spotify,
}

# ----------------------
# USER COMMANDS (easy place to add extra commands)
# ----------------------
# To add commands to run during setup, add dictionaries to USER_COMMANDS:
#  {"as_user": TARGET_USER, "cmd": "echo hello > ~/hello.txt"}
USER_COMMANDS: List[Dict[str, Any]] = [
    # Example (commented):
    # {"as_user": TARGET_USER, "cmd": f'XDG_RUNTIME_DIR=/run/user/{pwd.getpwnam(TARGET_USER).pw_uid} systemctl --user daemon-reexec'},
    # {"as_user": TARGET_USER, "cmd": f'XDG_RUNTIME_DIR=/run/user/{pwd.getpwnam(TARGET_USER).pw_uid} systemctl --user daemon-reload'},
    # {"as_user": TARGET_USER, "cmd": f'XDG_RUNTIME_DIR=/run/user/{pwd.getpwnam(TARGET_USER).pw_uid} systemctl --user restart battery-monitor.service'},
]

def run_user_commands():
    if not USER_COMMANDS:
        log.info("[USER-CMDS] No user commands defined.")
        return
    for entry in USER_COMMANDS:
        as_user = entry.get("as_user", "root")
        cmd = entry.get("cmd")
        if not cmd:
            continue
        try:
            if as_user == "root" or as_user.upper() == "ROOT":
                r = run(cmd, check=False, capture_output=True, shell=True)
            else:
                pw = pwd.getpwnam(as_user)
                uid = pw.pw_uid
                wrapper = f"XDG_RUNTIME_DIR=/run/user/{uid} {cmd}"
                r = run(["sudo", "-u", as_user, "bash", "-lc", wrapper], check=False, capture_output=True)
            rc = getattr(r, "returncode", 1)
            stdout = getattr(r, "stdout", "") or ""
            stderr = getattr(r, "stderr", "") or ""
            if rc == 0:
                log.info("[USER-CMDS] succeeded: %s", cmd)
                if stdout:
                    log.info("[USER-CMDS-OUT] %s", stdout.strip())
            else:
                log.warning("[USER-CMDS] rc=%s for cmd: %s", rc, cmd)
                if stdout:
                    log.warning("[USER-CMDS-OUT] %s", stdout.strip())
                if stderr:
                    log.warning("[USER-CMDS-ERR] %s", stderr.strip())
        except Exception as e:
            log.warning("[USER-CMDS] Exception running command %s: %s", cmd, e)


# ----------------------
# Interactive prompt for apps
# ----------------------
def prompt_multi_select() -> List[int]:
    lines = ["Select applications to install (enter numbers separated by spaces or commas):"]
    for k in sorted(APP_OPTIONS.keys()):
        lines.append(f" {k:2d}) {APP_OPTIONS[k]}")
    lines.append(" a) all")
    lines.append(" n) none (or just press Enter)")
    print("\n".join(lines))
    try:
        raw = input("Enter selection (e.g. '1 3 5' or 'a' for All): ").strip()
    except EOFError:
        log.info("[INPUT] EOF on selection; assuming 'none'.")
        return []
    if not raw:
        log.info("[INPUT] No selection entered; assuming 'none'.")
        return []
    raw_l = raw.strip().lower()
    if raw_l in ("all", "a"):
        return list(sorted(APP_OPTIONS.keys()))
    if raw_l in ("none", "n", "0"):
        return []
    tokens = []
    for part in raw.replace(",", " ").split():
        part = part.strip()
        if not part:
            continue
        if part.isdigit():
            try:
                v = int(part)
                if v in APP_OPTIONS:
                    tokens.append(v)
            except ValueError:
                continue
        else:
            for k, name in APP_OPTIONS.items():
                if part == name.lower() or part == name.split()[0].lower():
                    tokens.append(k)
    # de-duplicate preserving order
    result = []
    for k in tokens:
        if k not in result:
            result.append(k)
    return result


# ----------------------
# Main flow
# ----------------------
def main():
    require_root()

    # 1) Clone or detect repo
    startup_dir = detect_or_clone_repo()

    # 2) Install core apt packages (noninteractive)
    install_apt_packages(APT_PACKAGES)

    # 3) Copy configs from repo into user's home (backups made)
    copy_core_configs(startup_dir)

    # 4) Install battery monitor script + service (and run systemctl --user sequence)
    install_battery_monitor(startup_dir)

    # 5) Ensure scripts are executable and refresh i3 (Win+Shift+R simulation if i3 is running)
    set_executables_and_restart_i3()

    # 6) Run any USER_COMMANDS (if you added them to USER_COMMANDS)
    run_user_commands()

    # 7) Interactive app installation (Spotify included)
    selections = prompt_multi_select()
    if not selections:
        log.info("[INFO] No applications selected for installation.")
    else:
        log.info(f"[INFO] Installing selected applications: {selections}")
        for sel in selections:
            name = APP_OPTIONS.get(sel)
            if not name:
                log.warning("[WARN] Unknown selection %s; skipping.", sel)
                continue
            fn = INSTALL_DISPATCH.get(name)
            if not fn:
                log.warning("[WARN] No installer function for %s; skipping.", name)
                continue
            try:
                log.info("[INSTALL] Starting installer for %s", name)
                fn(startup_dir)
            except Exception as e:
                log.warning("[WARN] Installer for %s raised exception: %s", name, e)

    log.info("[DONE] Setup complete!")


if __name__ == "__main__":
    main()
