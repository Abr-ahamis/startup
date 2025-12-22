#!/usr/bin/env python3
"""
startup_setup_full.py  (FINAL - includes all requested behavior)

Key behavior (per your requests):
 - Detect/clone repo (REPO_URL)
 - Install APT packages non-interactively
 - Backup existing user config files and copy repo files into the user's home
 - Ensure ~/.local/bin exists and is in user's .bashrc PATH
 - Install battery-monitor script and user service (if present) and run the requested
       systemctl --user daemon-reexec
       systemctl --user daemon-reload
       systemctl --user restart battery-monitor.service
   executed as the target non-root user **without** XDG prefix first, then with XDG prefix if needed
 - Install system-wide rofi theme from repo:
       copy i3/usr/share/rofi/themes/Adapta-Nokto.rasi -> /usr/share/rofi/themes/Adapta-Nokto.rasi
   while taking a backup of /usr/share/rofi/themes and then removing other files (after backup)
 - Make scripts executable
 - If the target user is running i3: refresh i3 via Win+Shift+R using xdotool (tries DISPLAY/XAUTHORITY combos),
   fallback to i3-msg restart if necessary, then wait for i3 to respond
 - Interactive app install menu includes Spotify (and other apps you had earlier)
 - Logs every copy/backup/command/app-install attempt into a summary written to:
     - /var/log/startup_setup_full.log
     - /home/<TARGET_USER>/startup_setup_summary.txt
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

APT_PACKAGES = [
    "i3-wm", "i3blocks", "rofi", "xdotool", "dex", "acpi", "upower",
    "xfce4-power-manager", "i3lock", "xss-lock", "pulseaudio-utils",
    "brightnessctl", "feh", "picom", "fonts-font-awesome", "git", "rsync",
    "unzip", "curl", "wget", "grub-customizer", "timeshift"
]

# APP MENU: only Spotify was added per your instruction.
APP_OPTIONS = {
    1: "telegram",
    2: "brave-nightly",
    3: "vscode",
    4: "protonvpn",
    5: "virtualbox",
    6: "rustscan",
    7: "spotify",
}

# Log file (root-writable)
SYSTEM_LOG = Path("/var/log/startup_setup_full.log")

# ----------------------
# Logging setup
# ----------------------
logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
log = logging.getLogger("startup_setup")

# Global actions tracker for the final summary (keeps entries of what the script did)
ACTIONS_LOG: List[str] = []

# ----------------------
# Environment / user detection
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

# Ensure system log file exists and is writable (script runs as root)
try:
    SYSTEM_LOG.parent.mkdir(parents=True, exist_ok=True)
    if not SYSTEM_LOG.exists():
        SYSTEM_LOG.write_text(f"startup_setup_full log created {datetime.datetime.now().isoformat()}\n")
    ACTIONS_LOG.append(f"Log file initialized: {SYSTEM_LOG}")
except Exception as e:
    log.warning(f"Could not create system log {SYSTEM_LOG}: {e}")

def die(msg: str, code: int = 1):
    log.error(msg)
    ACTIONS_LOG.append(f"FATAL: {msg}")
    write_summary_logs()
    sys.exit(code)


def run(cmd, check: bool = False, capture_output: bool = False, env: Optional[dict] = None, shell: bool = False):
    """
    Wrapper around subprocess.run for consistent logging.
    Accepts list or string.
    """
    if isinstance(cmd, (list, tuple)):
        log.info(f"[CMD] {' '.join(map(str, cmd))}")
    else:
        log.info(f"[CMD] {cmd}")
    try:
        return subprocess.run(cmd, check=check, capture_output=capture_output, text=True, env=env, shell=shell)
    except subprocess.CalledProcessError as e:
        if capture_output:
            log.warning("stdout: %s", e.stdout)
            log.warning("stderr: %s", e.stderr)
        if check:
            raise
        return e


def ensure_dir(p: Path, mode: int = 0o755):
    if not p.exists():
        log.info(f"[MKDIR] {p}")
        try:
            p.mkdir(parents=True, mode=mode, exist_ok=True)
        except Exception as e:
            log.warning(f"[MKDIR] failed {p}: {e}")
    else:
        log.debug(f"[MKDIR] exists {p}")


def unique_backup_name(p: Path) -> Path:
    base = p.with_name(p.name + ".backup")
    if not base.exists():
        return base
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    return p.with_name(p.name + f".backup.{ts}")


def backup_existing(dst: Path) -> Optional[Path]:
    """
    Rename dst -> dst.backup or dst.backup.TIMESTAMP if needed.
    """
    try:
        if not dst.exists():
            return None
        b = unique_backup_name(dst)
        log.info(f"[BACKUP] Renaming {dst} -> {b}")
        shutil.move(str(dst), str(b))
        ACTIONS_LOG.append(f"Backed up {dst} -> {b}")
        return b
    except Exception as e:
        log.warning(f"[WARN] Failed to backup {dst}: {e}")
        ACTIONS_LOG.append(f"Failed to backup {dst}: {e}")
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
        ACTIONS_LOG.append(f"chown failed for {path}: {e}")


def safe_copy(src: Path, dst: Path, make_backup: bool = True, dirs_exist_ok: bool = False) -> bool:
    """
    Copy src -> dst safely. Records action into ACTIONS_LOG.
    """
    src = Path(src)
    dst = Path(dst)
    if not src.exists():
        log.info(f"[SKIP] Source not found: {src}")
        ACTIONS_LOG.append(f"SKIP copy missing: {src} -> {dst}")
        return False
    ensure_dir(dst.parent)
    if dst.exists():
        if make_backup:
            backup_existing(dst)
        else:
            try:
                if dst.is_dir():
                    shutil.rmtree(dst, ignore_errors=True)
                else:
                    dst.unlink()
            except Exception:
                pass
    try:
        if src.is_dir():
            log.info(f"[COPY-DIR] {src} -> {dst}")
            shutil.copytree(src, dst, dirs_exist_ok=dirs_exist_ok)
            ACTIONS_LOG.append(f"COPY-DIR {src} -> {dst}")
        else:
            log.info(f"[COPY-FILE] {src} -> {dst}")
            shutil.copy2(src, dst)
            ACTIONS_LOG.append(f"COPY-FILE {src} -> {dst}")
        try:
            chown_recursive(dst, TARGET_USER)
        except Exception:
            pass
        return True
    except Exception as e:
        log.warning(f"[WARN] Copy failed {src} -> {dst}: {e}")
        ACTIONS_LOG.append(f"COPY-FAILED {src} -> {dst}: {e}")
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
        ACTIONS_LOG.append(f"Using current dir as repo: {cwd}")
        return cwd
    if (cwd / REPO_DIR_NAME).is_dir():
        log.info(f"[INFO] Found ./{REPO_DIR_NAME}; using it.")
        ACTIONS_LOG.append(f"Found ./{REPO_DIR_NAME}")
        return cwd / REPO_DIR_NAME
    target = cwd / REPO_DIR_NAME
    if target.exists():
        ACTIONS_LOG.append(f"Using existing {target}")
        return target
    log.info(f"[INFO] Cloning {REPO_URL} -> {target}")
    r = run(["git", "clone", REPO_URL, str(target)], check=False, capture_output=True)
    rc = getattr(r, "returncode", 1)
    if rc != 0:
        log.warning("[WARN] git clone returned non-zero; continuing in case repo exists locally.")
        ACTIONS_LOG.append(f"git clone rc={rc}")
    else:
        ACTIONS_LOG.append(f"git clone {REPO_URL} -> {target}")
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
    ACTIONS_LOG.append(f"apt install attempted: {len(packages)} packages")


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

    # i3blocks, rofi, picom
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
    try:
        if bashrc.exists():
            content = bashrc.read_text()
            if path_line not in content:
                log.info("[PATH] Appending PATH line to .bashrc")
                with open(bashrc, "a") as fh:
                    fh.write(f"\n{path_line}\n")
                ACTIONS_LOG.append("Appended PATH to .bashrc")
            else:
                log.info("[PATH] PATH already present in .bashrc")
        else:
            log.info("[PATH] .bashrc not found, creating one with PATH line.")
            with open(bashrc, "w") as fh:
                fh.write(f"{path_line}\n")
            ACTIONS_LOG.append("Created .bashrc with PATH")
    except Exception as e:
        log.warning("[PATH] Could not update .bashrc: %s", e)
        ACTIONS_LOG.append(f".bashrc update failed: {e}")

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
                ACTIONS_LOG.append(f"Copied wallpaper to {backgrounds_dir}/{name}")
            except Exception as e:
                log.warning(f"[WARN] copying wallpaper to system backgrounds failed: {e}")
                ACTIONS_LOG.append(f"Failed copying wallpaper to system: {e}")


# ----------------------
# Helper: run systemctl --user sequence (first attempt without XDG, then fallback with XDG)
# ----------------------
def run_systemctl_user_sequence():
    """
    Attempt to run, as the target user, the exact three commands **without** XDG_RUNTIME_DIR prefix first.
    If they fail (return non-zero or indicate cannot connect to bus), retry with XDG_RUNTIME_DIR=/run/user/<UID>.
    Logs results to ACTIONS_LOG.
    """
    try:
        pw = pwd.getpwnam(TARGET_USER)
        uid = pw.pw_uid
    except Exception as e:
        log.warning("[SYSTEMCTL] Could not find user %s: %s", TARGET_USER, e)
        ACTIONS_LOG.append(f"systemctl sequence skipped - user lookup failed: {e}")
        return

    cmds_noprefix = [
        ["sudo", "-u", TARGET_USER, "systemctl", "--user", "daemon-reexec"],
        ["sudo", "-u", TARGET_USER, "systemctl", "--user", "daemon-reload"],
        ["sudo", "-u", TARGET_USER, "systemctl", "--user", "restart", "battery-monitor.service"],
    ]
    cmds_with_xdg = [
        ["sudo", "-u", TARGET_USER, "bash", "-lc", f"XDG_RUNTIME_DIR=/run/user/{uid} systemctl --user daemon-reexec"],
        ["sudo", "-u", TARGET_USER, "bash", "-lc", f"XDG_RUNTIME_DIR=/run/user/{uid} systemctl --user daemon-reload"],
        ["sudo", "-u", TARGET_USER, "bash", "-lc", f"XDG_RUNTIME_DIR=/run/user/{uid} systemctl --user restart battery-monitor.service"],
    ]

    success_all = True
    # Try no-prefix first
    for c in cmds_noprefix:
        r = run(c, check=False, capture_output=True)
        rc = getattr(r, "returncode", 1)
        stdout = (getattr(r, "stdout", "") or "").strip()
        stderr = (getattr(r, "stderr", "") or "").strip()
        ACTIONS_LOG.append(f"Ran (no XDG): {' '.join(c)} rc={rc}")
        if rc == 0:
            log.info("[SYSTEMCTL] succeeded: %s", " ".join(c))
            if stdout:
                log.info("[SYSTEMCTL-OUT] %s", stdout)
        else:
            log.warning("[SYSTEMCTL] failed (no XDG) rc=%s: %s", rc, " ".join(c))
            if stderr:
                log.warning("[SYSTEMCTL-ERR] %s", stderr)
            success_all = False

    if success_all:
        ACTIONS_LOG.append("systemctl sequence completed successfully (no XDG)")
        return

    # If no-prefix failed, attempt prefixed variant for reliability
    log.info("[SYSTEMCTL] Falling back to XDG_RUNTIME_DIR-prefixed commands for reliability.")
    for c in cmds_with_xdg:
        r = run(c, check=False, capture_output=True, shell=False)
        rc = getattr(r, "returncode", 1)
        stdout = (getattr(r, "stdout", "") or "").strip()
        stderr = (getattr(r, "stderr", "") or "").strip()
        ACTIONS_LOG.append(f"Ran (with XDG): {c} rc={rc}")
        if rc == 0:
            log.info("[SYSTEMCTL] succeeded (with XDG): %s", c)
            if stdout:
                log.info("[SYSTEMCTL-OUT] %s", stdout)
        else:
            log.warning("[SYSTEMCTL] failed (with XDG) rc=%s: %s", rc, c)
            if stderr:
                log.warning("[SYSTEMCTL-ERR] %s", stderr)
    ACTIONS_LOG.append("systemctl sequence attempted (with fallback)")


# ----------------------
# Install battery monitor script + service and run user systemctl sequence
# ----------------------
def install_battery_monitor(startup_dir: Path):
    repo_script = startup_dir / "i3" / ".local" / "bin" / "battery-monitor.sh"
    repo_service = startup_dir / "i3" / ".config" / "systemd" / "user" / "battery-monitor.service"

    dst_script = USER_HOME / ".local" / "bin" / "battery-monitor.sh"
    dst_service = USER_HOME / ".config" / "systemd" / "user" / "battery-monitor.service"

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
            ACTIONS_LOG.append(f"Installed battery-monitor script -> {dst_script}")
            log.info("[BATTERY] Installed battery-monitor script to %s", dst_script)
    else:
        log.info("[BATTERY] No battery-monitor script found in repo; skipping script install.")
        ACTIONS_LOG.append("No battery-monitor script in repo")

    if repo_service.exists():
        ensure_dir(dst_service.parent)
        if safe_copy(repo_service, dst_service, make_backup=True):
            try:
                chown_recursive(dst_service, TARGET_USER)
            except Exception:
                pass
            ACTIONS_LOG.append(f"Installed battery-monitor service -> {dst_service}")
            log.info("[BATTERY] Installed battery-monitor user service to %s", dst_service)

            # ensure DBUS environment line present in [Service]
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
                    chown_recursive(dst_service, TARGET_USER)
                    ACTIONS_LOG.append("Injected DBUS env into battery-monitor.service")
                    log.info("[BATTERY] Injected DBUS Environment line into %s", dst_service)
            except Exception as e:
                log.warning(f"[BATTERY] Could not ensure DBUS env in service file: {e}")
                ACTIONS_LOG.append(f"Failed to inject DBUS env: {e}")
    else:
        log.info("[BATTERY] No battery-monitor.service found in repo; skipping service install.")
        ACTIONS_LOG.append("No battery-monitor.service in repo")

    # Run user-level systemctl commands (attempt no-prefix then fallback with XDG)
    run_systemctl_user_sequence()


# ----------------------
# Install system-wide rofi theme from repo (backup, copy, remove others)
# ----------------------
def install_system_rofi_theme_from_repo(startup_dir: Path):
    """
    - Back up /usr/share/rofi/themes -> /usr/share/rofi/themes.backup.TIMESTAMP
    - Copy repo/i3/usr/share/rofi/themes/Adapta-Nokto.rasi -> /usr/share/rofi/themes/Adapta-Nokto.rasi
    - Remove other files in /usr/share/rofi/themes (after backup)
    - Re-run systemctl --user sequence for the target user (no-prefix then fallback)
    """
    repo_theme = startup_dir / "i3" / "usr" / "share" / "rofi" / "themes" / "Adapta-Nokto.rasi"
    dst_dir = Path("/usr/share/rofi/themes")
    if not repo_theme.exists():
        log.info("[ROFI-THEME] Repo theme not found at %s; skipping.", repo_theme)
        ACTIONS_LOG.append(f"ROFI theme not found in repo: {repo_theme}")
        return

    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_dir = dst_dir.parent / f"themes.backup.{ts}"
    try:
        # Backup existing themes directory
        if dst_dir.exists():
            log.info("[ROFI-THEME] Backing up %s -> %s", dst_dir, backup_dir)
            if backup_dir.exists():
                shutil.rmtree(backup_dir, ignore_errors=True)
            shutil.copytree(dst_dir, backup_dir)
            ACTIONS_LOG.append(f"Backed up /usr/share/rofi/themes -> {backup_dir}")
        else:
            ensure_dir(dst_dir)
            ACTIONS_LOG.append(f"Created /usr/share/rofi/themes directory")

        # Copy the new theme file into place (overwrite if exists)
        dest_theme = dst_dir / "Adapta-Nokto.rasi"
        log.info("[ROFI-THEME] Installing %s -> %s", repo_theme, dest_theme)
        shutil.copy2(repo_theme, dest_theme)
        ACTIONS_LOG.append(f"Installed rofi theme {repo_theme} -> {dest_theme}")

        # Remove other files in the themes directory (only after backup)
        for p in dst_dir.iterdir():
            if p.is_file() and p.name != dest_theme.name:
                try:
                    log.info("[ROFI-THEME] Removing other theme file: %s", p)
                    ACTIONS_LOG.append(f"Removing theme file: {p}")
                    p.unlink()
                except Exception as e:
                    log.warning("[ROFI-THEME] Could not remove %s: %s", p, e)
                    ACTIONS_LOG.append(f"Failed remove theme file {p}: {e}")

        # Fix permissions: files readable by all
        try:
            for p in dst_dir.iterdir():
                if p.is_file():
                    p.chmod(0o644)
        except Exception:
            pass

        ACTIONS_LOG.append(f"ROFI theme installed and other themes removed; backup at {backup_dir}")
        log.info("[ROFI-THEME] System rofi theme installed. Backup stored at %s", backup_dir)
    except Exception as e:
        log.warning("[ROFI-THEME] Failed to install system rofi theme: %s", e)
        ACTIONS_LOG.append(f"ROFI theme install failed: {e}")
        # Try to restore backup if we broke something
        try:
            if backup_dir.exists() and dst_dir.exists():
                shutil.rmtree(dst_dir, ignore_errors=True)
                shutil.copytree(backup_dir, dst_dir)
                ACTIONS_LOG.append(f"Restored theme backup from {backup_dir}")
        except Exception as e2:
            log.warning("[ROFI-THEME] Could not restore backup: %s", e2)
            ACTIONS_LOG.append(f"Failed to restore theme backup: {e2}")

    # Re-run user systemctl sequence because we changed system files
    run_systemctl_user_sequence()


# ----------------------
# i3 detection and refresh helpers
# ----------------------
def is_user_running_i3() -> bool:
    """
    Detect if the target user is running i3:
      1) pgrep -u <uid> -x i3
      2) fallback: i3-msg -t get_version as the user
    """
    try:
        pw = pwd.getpwnam(TARGET_USER)
        uid = pw.pw_uid
    except Exception:
        log.warning("[I3-CHECK] Could not lookup user %s", TARGET_USER)
        return False

    try:
        r = run(["pgrep", "-u", str(uid), "-x", "i3"], check=False, capture_output=True)
        if getattr(r, "returncode", 1) == 0:
            ACTIONS_LOG.append(f"Detected i3 via pgrep for {TARGET_USER}")
            log.info("[I3-CHECK] Found i3 process for user %s (pgrep).", TARGET_USER)
            return True
    except Exception:
        pass

    # fallback to i3-msg
    try:
        r = run(["sudo", "-u", TARGET_USER, "bash", "-lc", f"i3-msg -t get_version"], check=False, capture_output=True)
        rc = getattr(r, "returncode", 1)
        out = (getattr(r, "stdout", "") or "").strip()
        if rc == 0 and out:
            ACTIONS_LOG.append(f"Detected i3 via i3-msg for {TARGET_USER}")
            log.info("[I3-CHECK] i3 responded to i3-msg for user %s.", TARGET_USER)
            return True
    except Exception:
        pass

    log.info("[I3-CHECK] No i3 session detected for user %s; skipping refresh.", TARGET_USER)
    return False


def try_send_xdotool_refresh(timeout: int = 5) -> bool:
    """
    Simulate Win+Shift+R (Super+Shift+r) via xdotool for the user's X session.
    Tries several DISPLAY / XAUTHORITY combinations.
    """
    displays = [":0", ":0.0", ":1"]
    xauth_candidates = [
        str(USER_HOME / ".Xauthority"),
        f"/run/user/{pwd.getpwnam(TARGET_USER).pw_uid}/gdm/Xauthority" if Path(f"/run/user/{pwd.getpwnam(TARGET_USER).pw_uid}/gdm").exists() else "",
    ]
    key_cmd = "xdotool keydown Super keydown Shift key r keyup Shift keyup Super"

    for disp in displays:
        for xauth in [p for p in xauth_candidates if p]:
            wrapper = f'export DISPLAY="{disp}" && export XAUTHORITY="{xauth}" && {key_cmd}'
            cmd = ["sudo", "-u", TARGET_USER, "bash", "-lc", wrapper]
            log.info("[I3-REFRESH] Trying xdotool on DISPLAY=%s XAUTHORITY=%s", disp, xauth)
            A = run(cmd, check=False, capture_output=True)
            rc = getattr(A, "returncode", 1)
            if rc == 0:
                ACTIONS_LOG.append(f"xdotool refresh succeeded on DISPLAY={disp} XAUTHORITY={xauth}")
                log.info("[I3-REFRESH] xdotool success on %s", disp)
                return True
            else:
                log.debug("[I3-REFRESH] xdotool failed on %s rc=%s", disp, rc)

    # try without XAUTHORITY
    for disp in displays:
        wrapper = f'export DISPLAY="{disp}" && {key_cmd}'
        cmd = ["sudo", "-u", TARGET_USER, "bash", "-lc", wrapper]
        log.info("[I3-REFRESH] Trying xdotool on DISPLAY=%s (no XAUTHORITY)", disp)
        A = run(cmd, check=False, capture_output=True)
        rc = getattr(A, "returncode", 1)
        if rc == 0:
            ACTIONS_LOG.append(f"xdotool refresh succeeded on DISPLAY={disp} (no XAUTHORITY)")
            log.info("[I3-REFRESH] xdotool success on %s (no XAUTHORITY)", disp)
            return True

    log.warning("[I3-REFRESH] xdotool attempts failed (xdotool may be missing or no X session).")
    ACTIONS_LOG.append("xdotool refresh attempts failed")
    return False


def wait_for_i3_ready(timeout: int = 20) -> bool:
    log.info("[I3-WAIT] Waiting for i3 to be ready (timeout %ds)...", timeout)
    start = time.time()
    while time.time() - start < timeout:
        try:
            r = run(["sudo", "-u", TARGET_USER, "bash", "-lc", "i3-msg -t get_version"], check=False, capture_output=True)
            rc = getattr(r, "returncode", 1)
            out = (getattr(r, "stdout", "") or "").strip()
            if rc == 0 and out:
                ACTIONS_LOG.append("i3 responded after refresh")
                log.info("[I3-WAIT] i3 responded.")
                return True
        except Exception:
            pass
        time.sleep(1)
    log.warning("[I3-WAIT] i3 did not respond within %d seconds.", timeout)
    ACTIONS_LOG.append("i3 did not respond within timeout")
    return False


def set_executables_and_restart_i3():
    """
    Make scripts executable; if the user is running i3, attempt a keyboard refresh (xdotool) to simulate Win+Shift+R.
    Fallback to i3-msg restart if needed. If the user isn't running i3, skip refresh.
    """
    # make scripts executable
    scripts_dir = USER_HOME / ".config" / "i3blocks" / "scripts"
    if scripts_dir.exists():
        for sh in scripts_dir.glob("*.sh"):
            try:
                sh.chmod(0o755)
                ACTIONS_LOG.append(f"chmod +x {sh}")
            except Exception:
                pass

    rofi_dir = USER_HOME / ".config" / "rofi"
    if rofi_dir.exists():
        for f in rofi_dir.rglob("*.sh"):
            try:
                f.chmod(0o755)
                ACTIONS_LOG.append(f"chmod +x {f}")
            except Exception:
                pass

    i3_scripts_dir = USER_HOME / ".config" / "i3" / "scripts"
    if i3_scripts_dir.exists():
        for f in i3_scripts_dir.iterdir():
            if f.is_file():
                try:
                    f.chmod(0o755)
                    ACTIONS_LOG.append(f"chmod +x {f}")
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

    # Only attempt refresh if user is running i3
    if not is_user_running_i3():
        ACTIONS_LOG.append("Skipped i3 refresh: user not running i3")
        return

    # Try xdotool refresh
    refreshed = False
    try:
        r = run(["which", "xdotool"], check=False, capture_output=True)
        if getattr(r, "returncode", 1) == 0 and (getattr(r, "stdout", "") or "").strip():
            refreshed = try_send_xdotool_refresh()
        else:
            log.info("[I3-REFRESH] xdotool not installed; skipping keypress method.")
            ACTIONS_LOG.append("xdotool not installed")
    except Exception as e:
        log.warning("[I3-REFRESH] Exception checking xdotool: %s", e)
        ACTIONS_LOG.append(f"xdotool check exception: {e}")

    # Fallback to i3-msg restart if xdotool failed
    if not refreshed:
        try:
            log.info("[I3-REFRESH] Falling back to i3-msg restart (best-effort).")
            run(["sudo", "-u", TARGET_USER, "i3-msg", "restart"], check=False, capture_output=True)
            ACTIONS_LOG.append("Ran i3-msg restart (fallback)")
        except Exception as e:
            log.warning(f"[WARN] Could not run i3-msg restart: {e}")
            ACTIONS_LOG.append(f"i3-msg restart failed: {e}")

    # Wait for i3
    ok = wait_for_i3_ready(timeout=20)
    if ok:
        ACTIONS_LOG.append("i3 ready after refresh")
    else:
        ACTIONS_LOG.append("i3 not ready after refresh - continuing anyway")


# ----------------------
# App installers (unchanged core logic; best-effort)
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
            ACTIONS_LOG.append("Telegram installed and symlinked /usr/local/bin/telegram")
            log.info(f"[TELEGRAM] Created symlink {link} -> {tbin}")
        except Exception as e:
            log.warning(f"[WARN] Could not create symlink for telegram: {e}")
            ACTIONS_LOG.append(f"Telegram symlink failed: {e}")
    else:
        log.warning("[WARN] Telegram binary not found after extraction.")
        ACTIONS_LOG.append("Telegram extraction failed")


def install_brave_nightly(startup_dir: Optional[Path] = None):
    log.info("[BRAVE] Installing Brave (nightly) — best-effort.")
    run('curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly bash', check=False, shell=True)
    run(["apt", "install", "-y", "brave-browser-nightly"], check=False)
    ACTIONS_LOG.append("Brave nightly install attempted")


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
    ACTIONS_LOG.append("VSCode install attempted")


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
    ACTIONS_LOG.append("ProtonVPN install attempted")


def install_virtualbox(startup_dir: Optional[Path] = None):
    log.info("[VBOX] Installing VirtualBox (from apt) — best-effort.")
    run(["apt", "update"], check=False)
    run(["apt", "install", "-y", "virtualbox"], check=False)
    ACTIONS_LOG.append("VirtualBox install attempted")


def install_rustscan(startup_dir: Optional[Path] = None):
    log.info("[RUSTSCAN] Installing RustScan (.deb) — best-effort.")
    deb = Path("/tmp/rustscan_2.2.3_amd64.deb")
    url = "https://github.com/RustScan/RustScan/releases/download/2.2.3/rustscan_2.2.3_amd64.deb"
    run(["wget", "-q", url, "-O", str(deb)], check=False)
    if deb.exists():
        r = run(["dpkg", "-i", str(deb)], check=False)
        if getattr(r, "returncode", 0) != 0:
            run(["apt", "install", "-f", "-y"], check=False)
    ACTIONS_LOG.append("RustScan install attempted")


def install_spotify(startup_dir: Optional[Path] = None):
    log.info("[SPOTIFY] Installing Spotify (best-effort).")
    try:
        run(["apt", "update"], check=False)
        run(["bash", "-lc", "curl -sS https://download.spotify.com/debian/pubkey_0D811D58.gpg | gpg --dearmor -o /usr/share/keyrings/spotify-archive-keyring.gpg"], check=False, shell=True)
        list_file = Path("/etc/apt/sources.list.d/spotify.list")
        list_content = "deb [signed-by=/usr/share/keyrings/spotify-archive-keyring.gpg] http://repository.spotify.com stable non-free\n"
        try:
            list_file.write_text(list_content)
        except Exception as e:
            log.warning("[SPOTIFY] Could not write sources.list: %s", e)
        run(["apt", "update"], check=False)
        run(["apt", "install", "-y", "spotify-client"], check=False)
        ACTIONS_LOG.append("Spotify apt install attempted")
    except Exception as e:
        log.warning("[SPOTIFY] apt-based install failed: %s", e)
        ACTIONS_LOG.append(f"Spotify apt failed: {e}")
    # fallback snap
    try:
        run(["snap", "install", "spotify"], check=False)
        ACTIONS_LOG.append("Spotify snap install attempted")
    except Exception:
        pass


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
# USER_COMMANDS (edit to add custom commands)
# ----------------------
# Add arbitrary commands to run during setup. Example:
# USER_COMMANDS = [
#   {"as_user": TARGET_USER, "cmd": "echo hello > ~/hello.txt"},
#   {"as_user": "root", "cmd": "echo rootcmd >/tmp/rootcmd.txt"}
# ]
USER_COMMANDS: List[Dict[str, Any]] = []


def run_user_commands():
    if not USER_COMMANDS:
        ACTIONS_LOG.append("No USER_COMMANDS defined")
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
            ACTIONS_LOG.append(f"Ran USER_COMMAND as {as_user}: {cmd} rc={rc}")
            if rc != 0:
                ACTIONS_LOG.append(f"USER_COMMAND stderr: {getattr(r,'stderr','')}")
        except Exception as e:
            ACTIONS_LOG.append(f"USER_COMMAND exception: {e}")


# ----------------------
# Interactive prompts
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
# Summary writer
# ----------------------
def write_summary_logs():
    # Write actions log to system log and user's summary file
    try:
        with open(SYSTEM_LOG, "a") as fh:
            fh.write(f"\n----- run at {datetime.datetime.now().isoformat()} -----\n")
            for a in ACTIONS_LOG:
                fh.write(a + "\n")
    except Exception as e:
        log.warning(f"Failed to write system log: {e}")

    try:
        user_summary = USER_HOME / "startup_setup_summary.txt"
        with open(user_summary, "a") as fh:
            fh.write(f"\n----- run at {datetime.datetime.now().isoformat()} -----\n")
            for a in ACTIONS_LOG:
                fh.write(a + "\n")
        # chown it to user
        try:
            chown_recursive(user_summary, TARGET_USER)
        except Exception:
            pass
    except Exception as e:
        log.warning(f"Failed to write user summary: {e}")


# ----------------------
# Main flow
# ----------------------
def main():
    require_root()

    # 1) Clone or detect repo
    startup_dir = detect_or_clone_repo()

    # 2) Install core apt packages
    install_apt_packages(APT_PACKAGES)

    # 3) Copy configs into user's home (backups made)
    copy_core_configs(startup_dir)

    # 3.b) Install system-wide rofi theme from repo (backup -> install -> remove others)
    install_system_rofi_theme_from_repo(startup_dir)

    # 4) Install battery monitor script + service (and run user systemctl sequence)
    install_battery_monitor(startup_dir)

    # 5) Make scripts executable and refresh i3 (if running)
    set_executables_and_restart_i3()

    # 6) Run any USER_COMMANDS
    run_user_commands()

    # 7) Interactive app installation
    selections = prompt_multi_select()
    if not selections:
        log.info("[INFO] No applications selected for installation.")
        ACTIONS_LOG.append("No apps selected for installation")
    else:
        log.info(f"[INFO] Installing selected applications: {selections}")
        for sel in selections:
            name = APP_OPTIONS.get(sel)
            if not name:
                log.warning("[WARN] Unknown selection %s; skipping.", sel)
                ACTIONS_LOG.append(f"Unknown selection {sel}")
                continue
            fn = INSTALL_DISPATCH.get(name)
            if not fn:
                log.warning("[WARN] No installer function for %s; skipping.", name)
                ACTIONS_LOG.append(f"No installer for {name}")
                continue
            try:
                log.info("[INSTALL] Starting installer for %s", name)
                ACTIONS_LOG.append(f"Starting installer for {name}")
                fn(startup_dir)
            except Exception as e:
                log.warning("[WARN] Installer for %s raised exception: %s", name, e)
                ACTIONS_LOG.append(f"Installer {name} exception: {e}")

    ACTIONS_LOG.append("Setup complete")
    write_summary_logs()
    log.info("[DONE] Setup complete! Summary written to system log and user summary file.")


if __name__ == "__main__":
    main()
