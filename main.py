#!/usr/bin/env python3
"""
startup_setup_full.py

Upgraded and hardened Python version of your startup setup script.

Purpose:
  - Clone/detect a "startup" repo (contains i3, rofi, picom, i3blocks, wallpaper, grub, etc.)
  - Install required apt packages first (non-interactive, best-effort)
  - Carefully backup existing config files (append .backup, add timestamp if needed)
  - Copy repo configuration files into the correct user locations
  - Ensure ~/.local/bin is present and in the user's PATH (.bashrc update)
  - Make scripts executable and restart i3 (as the user) if running
  - Optionally apply GRUB theme and rotate/replace system wallpapers (rename old files with timestamp)
  - Interactive multi-select menu to install apps (Telegram, Brave nightly, VSCode, ProtonVPN, VirtualBox, RustScan)
  - After Telegram install, create a symlink so user can run `telegram` from terminal
  - Detailed, safe error handling and informative logging

Usage:
  sudo python3 startup_setup_full.py

Notes:
  - The script tries to be robust and "best-effort". Non-fatal problems are logged and the script continues.
  - It makes backups of existing user configuration files by renaming them to .backup (with timestamp if necessary).
  - Always read the script before running. Test with a VM or set DRY_RUN=True at top for a non-destructive preview.
"""
from __future__ import annotations
import os
import sys
import shutil
import subprocess
import datetime
import logging
from pathlib import Path
from typing import List, Optional
import pwd

# ----------------------
# CONFIG
# ----------------------
REPO_URL = "https://github.com/Abr-ahamis/startup.git"
REPO_DIR_NAME = "startup"
DRY_RUN = False  # set True to simulate operations (no destructive actions)

APT_PACKAGES = [
    "i3-wm", "i3blocks", "rofi", "xdotool", "dex", "acpi", "upower",
    "xfce4-power-manager", "i3lock", "xss-lock", "pulseaudio-utils",
    "brightnessctl", "feh", "picom", "fonts-font-awesome", "git", "rsync",
    "unzip", "curl", "wget", "grub-customizer", "timeshift"
]

# App options mapping (display only)
APP_OPTIONS = {
    1: "telegram",
    2: "brave-nightly",
    3: "vscode",
    4: "protonvpn",
    5: "virtualbox",
    6: "rustscan",
}

TIMESTAMP = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")

# ----------------------
# Logging
# ----------------------
logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
log = logging.getLogger("startup_setup")

# ----------------------
# Helpers & Environment
# ----------------------
def die(msg: str, code: int = 1):
    log.error(msg)
    sys.exit(code)


def run(cmd, check: bool = False, capture_output: bool = True, env: Optional[dict] = None, shell: bool = False):
    """
    Runs a command safely. Returns subprocess.CompletedProcess-like object with .returncode, .stdout, .stderr
    Non-fatal by default (check=False).
    """
    if DRY_RUN:
        log.info(f"[DRY-RUN CMD] {cmd}")
        class D:
            returncode = 0
            stdout = ""
            stderr = ""
        return D()

    if isinstance(cmd, (list, tuple)):
        log.info(f"[CMD] {' '.join(map(str, cmd))}")
    else:
        log.info(f"[CMD] {cmd}")

    try:
        completed = subprocess.run(cmd, check=check, capture_output=capture_output, text=True, env=env, shell=shell)
        if completed.stdout:
            log.debug(f"[OUT] {completed.stdout.strip()}")
        if completed.stderr:
            log.debug(f"[ERR] {completed.stderr.strip()}")
        return completed
    except subprocess.CalledProcessError as e:
        log.warning(f"[CMD-FAIL] returncode={e.returncode} cmd={e.cmd}")
        return e

def command_exists(name: str) -> bool:
    return shutil.which(name) is not None

def get_target_user() -> str:
    sudo_user = os.environ.get("SUDO_USER")
    if sudo_user:
        return sudo_user
    return os.environ.get("USER", "root")

TARGET_USER = get_target_user()
try:
    USER_HOME = Path(pwd.getpwnam(TARGET_USER).pw_dir)
except Exception:
    USER_HOME = Path(os.environ.get("HOME", "/root"))

log.info(f"Target user: {TARGET_USER}, home: {USER_HOME}")

def ensure_dir(p: Path, mode: int = 0o755):
    try:
        if not p.exists():
            if DRY_RUN:
                log.info(f"[DRY-RUN MKDIR] {p}")
            else:
                p.mkdir(parents=True, mode=mode, exist_ok=True)
                log.info(f"[MKDIR] {p}")
    except Exception as e:
        log.warning(f"[WARN] Could not create {p}: {e}")

def unique_backup_name(p: Path) -> Path:
    base = p.with_name(p.name + ".backup")
    if not base.exists():
        return base
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    return p.with_name(p.name + f".backup.{ts}")

def backup_existing(dst: Path) -> Optional[Path]:
    """
    If dst exists, rename to dst.backup (or dst.backup.TIMESTAMP).
    Returns new backup path or None if nothing was backed up.
    """
    if not dst.exists():
        return None
    b = unique_backup_name(dst)
    try:
        if DRY_RUN:
            log.info(f"[DRY-BACKUP] {dst} -> {b}")
        else:
            shutil.move(str(dst), str(b))
            log.info(f"[BACKUP] {dst} -> {b}")
        return b
    except Exception as e:
        log.warning(f"[WARN] Failed to backup {dst}: {e}")
        return None

def chown_recursive(path: Path, user: str):
    try:
        pw = pwd.getpwnam(user)
        uid, gid = pw.pw_uid, pw.pw_gid
        if not path.exists():
            return
        if path.is_dir():
            for root, dirs, files in os.walk(path):
                try:
                    os.chown(root, uid, gid)
                except Exception:
                    pass
                for d in dirs:
                    try:
                        os.chown(os.path.join(root, d), uid, gid)
                    except Exception:
                        pass
                for f in files:
                    try:
                        os.chown(os.path.join(root, f), uid, gid)
                    except Exception:
                        pass
        else:
            try:
                os.chown(str(path), uid, gid)
            except Exception:
                pass
    except Exception as e:
        log.debug(f"[DEBUG] chown_recursive skipped: {e}")

def safe_copy(src: Path, dst: Path, make_backup: bool = True, dirs_exist_ok: bool = False) -> bool:
    """
    Copy src -> dst safely. Back up existing dst if requested.
    """
    if not src.exists():
        log.info(f"[SKIP] Source not found: {src}")
        return False
    ensure_dir(dst.parent)
    if dst.exists():
        if make_backup:
            backup_existing(dst)
        else:
            if dst.is_dir():
                if DRY_RUN:
                    log.info(f"[DRY-RM] {dst}")
                else:
                    shutil.rmtree(dst, ignore_errors=True)
                    log.info(f"[RM] {dst}")
            else:
                if DRY_RUN:
                    log.info(f"[DRY-RM] {dst}")
                else:
                    try:
                        dst.unlink()
                    except Exception:
                        pass
    try:
        if src.is_dir():
            if DRY_RUN:
                log.info(f"[DRY-COPYDIR] {src} -> {dst}")
            else:
                # copytree content into dst
                shutil.copytree(src, dst, dirs_exist_ok=dirs_exist_ok)
                log.info(f"[COPY-DIR] {src} -> {dst}")
        else:
            if DRY_RUN:
                log.info(f"[DRY-COPYFILE] {src} -> {dst}")
            else:
                shutil.copy2(src, dst)
                log.info(f"[COPY-FILE] {src} -> {dst}")
        # chown to target user
        if not DRY_RUN:
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
        die("This script must be run as root. Use: sudo python3 startup_setup_full.py")

# ----------------------
# Repo detection / cloning
# ----------------------
def detect_or_clone_repo() -> Path:
    cwd = Path.cwd()
    log.info(f"Working directory: {cwd}")
    # If layout exists in cwd
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
    if DRY_RUN:
        log.info("[DRY-RUN] Skipping actual git clone.")
        return target
    if not command_exists("git"):
        log.warning("[WARN] git not found; cannot clone. Place repo at ./startup or run after installing git.")
        return target
    r = run(["git", "clone", "--depth", "1", REPO_URL, str(target)], check=False, capture_output=True)
    rc = getattr(r, "returncode", 1)
    if rc != 0:
        log.warning("[WARN] git clone returned non-zero; continuing in case repo exists locally.")
    return target

# ----------------------
# APT package installation
# ----------------------
def install_apt_packages(packages: List[str]):
    if not packages:
        log.info("[APT] No packages to install.")
        return
    if DRY_RUN:
        log.info("[DRY-RUN] Would install apt packages: " + " ".join(packages))
        return
    if not command_exists("apt"):
        log.warning("[WARN] apt not found; skipping package installation.")
        return
    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    log.info("[APT] Running apt update...")
    run(["apt", "update"], check=False, capture_output=True, env=env)
    cmd = ["apt", "install", "-y"] + packages
    log.info(f"[APT] Installing {len(packages)} packages (best-effort).")
    run(cmd, check=False, capture_output=True, env=env)

# ----------------------
# Copy core configs
# ----------------------
def copy_core_configs(startup_dir: Path):
    log.info("[COPY] Copying configs from repo...")
    repo_i3 = startup_dir / "i3"

    # i3 config
    safe_copy(repo_i3 / ".config" / "i3" / "config", USER_HOME / ".config" / "i3" / "config", make_backup=True)

    # i3 scripts & i3blocks & rofi & picom
    safe_copy(repo_i3 / ".config" / "i3blocks", USER_HOME / ".config" / "i3blocks", make_backup=True, dirs_exist_ok=True)
    safe_copy(repo_i3 / ".config" / "rofi", USER_HOME / ".config" / "rofi", make_backup=True, dirs_exist_ok=True)
    safe_copy(repo_i3 / ".config" / "picom" / "picom.conf", USER_HOME / ".config" / "picom" / "picom.conf", make_backup=True)

    # local bin (scripts)
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
    # refresh font cache
    if not DRY_RUN:
        try:
            run(["sudo", "-u", TARGET_USER, "fc-cache", "-fv"], check=False)
        except Exception:
            pass

    # Ensure ~/.local/bin in .bashrc
    bashrc = USER_HOME / ".bashrc"
    path_line = 'export PATH="$HOME/.local/bin:$PATH"'
    try:
        if bashrc.exists():
            content = bashrc.read_text()
            if path_line not in content:
                with open(bashrc, "a") as fh:
                    fh.write(f"\n# added by startup_setup\n{path_line}\n")
                log.info("[PATH] Appended PATH line to .bashrc")
            else:
                log.info("[PATH] PATH already present in .bashrc")
        else:
            with open(bashrc, "w") as fh:
                fh.write(f"# created by startup_setup\n{path_line}\n")
            log.info("[PATH] Created .bashrc with PATH entry")
    except Exception as e:
        log.warning(f"[WARN] Could not ensure .bashrc PATH entry: {e}")
    # Update current process PATH so subsequent installs can find local bin
    os.environ["PATH"] = str(USER_HOME / ".local" / "bin") + ":" + os.environ.get("PATH", "")

    # system rofi theme
    src_rofi_sys = repo_i3 / "usr" / "share" / "rofi" / "themes"
    dst_rofi_sys = Path("/usr/share/rofi/themes")
    ensure_dir(dst_rofi_sys)
    if src_rofi_sys.exists():
        for f in sorted(src_rofi_sys.iterdir()):
            safe_copy(f, dst_rofi_sys / f.name, make_backup=True)

    # wallpapers: copy to user Pictures and rotate system backgrounds (rename old with timestamp)
    repo_wall = startup_dir / "wallpaper"
    ensure_dir(USER_HOME / "Pictures")
    for name in ("wallpaper.jpg", "wallpaper-1.jpg", "wallpaper-2.jpg"):
        s = repo_wall / name
        if s.exists():
            safe_copy(s, USER_HOME / "Pictures" / name, make_backup=True)
    # system backgrounds replacement with rename
    backgrounds_dir = Path("/usr/share/backgrounds/kali")
    ensure_dir(backgrounds_dir)
    mapping = [
        ("wallpaper-1.jpg", "login.svg"),
        ("wallpaper.jpg", "kali-maze-16x9.jpg"),
        ("wallpaper-2.jpg", "kali-tiles-16x9.jpg"),
        ("wallpaper-1.jpg", "kali-waves-16x9.png"),
        ("wallpaper.jpg", "kali-oleo-16x9.png"),
        ("wallpaper-2.jpg", "kali-tiles-purple-16x9.jpg"),
        ("wallpaper-1.jpg", "login-blurred"),
    ]
    for src_name, dst_name in mapping:
        s = repo_wall / src_name
        dst = backgrounds_dir / dst_name
        if dst.exists():
            bak = dst.with_name(dst.name + f".{TIMESTAMP}.bak")
            try:
                if DRY_RUN:
                    log.info(f"[DRY-Rename] {dst} -> {bak}")
                else:
                    dst.rename(bak)
                    log.info(f"[SYS-RENAME] {dst} -> {bak}")
            except Exception as e:
                log.warning(f"[WARN] Could not rename {dst}: {e}")
        if s.exists():
            try:
                if DRY_RUN:
                    log.info(f"[DRY-COPY] {s} -> {dst}")
                else:
                    shutil.copy2(s, dst)
                    log.info(f"[SYS-COPY] {s} -> {dst}")
            except Exception as e:
                log.warning(f"[WARN] Could not copy {s} -> {dst}: {e}")

# ----------------------
# Battery monitor install + systemd --user handling
# ----------------------
def install_battery_monitor(startup_dir: Path):
    repo_script = startup_dir / "i3" / ".local" / "bin" / "battery-monitor.sh"
    repo_service = startup_dir / "i3" / ".config" / "systemd" / "user" / "battery-monitor.service"
    dst_script = USER_HOME / ".local" / "bin" / "battery-monitor.sh"
    dst_service = USER_HOME / ".config" / "systemd" / "user" / "battery-monitor.service"

    if repo_script.exists():
        ensure_dir(dst_script.parent)
        safe_copy(repo_script, dst_script, make_backup=True)
        if not DRY_RUN:
            try:
                dst_script.chmod(0o755)
            except Exception:
                pass
            chown_recursive(dst_script, TARGET_USER)
            log.info(f"[BATTERY] Copied script to {dst_script}")
    else:
        log.info(f"[BATTERY] No battery script found at {repo_script}")

    if repo_service.exists():
        ensure_dir(dst_service.parent)
        safe_copy(repo_service, dst_service, make_backup=True)
        chown_recursive(dst_service, TARGET_USER)
        log.info(f"[BATTERY] Copied service to {dst_service}")
    else:
        log.info(f"[BATTERY] No battery service found at {repo_service}")

    # Attempt to reload/enable/start the user service (best-effort)
    try:
        pw = pwd.getpwnam(TARGET_USER)
        uid = pw.pw_uid
        runtime_dir = Path(f"/run/user/{uid}")
        if not runtime_dir.exists():
            log.warning(f"[BATTERY] /run/user/{uid} does not exist. The target user may not have an active session; systemctl --user may fail.")
        cmd_str = (
            f"XDG_RUNTIME_DIR=/run/user/{uid} systemctl --user daemon-reload && "
            f"XDG_RUNTIME_DIR=/run/user/{uid} systemctl --user enable --now battery-monitor.service"
        )
        if DRY_RUN:
            log.info(f"[DRY-RUN BATTERY] would run (as {TARGET_USER}): {cmd_str}")
        else:
            r = run(["sudo", "-u", TARGET_USER, "bash", "-lc", cmd_str], check=False, capture_output=True)
            rc = getattr(r, "returncode", 1)
            if rc == 0:
                log.info("[BATTERY] user service reload/enable attempted successfully.")
            else:
                log.warning("[BATTERY] user systemctl returned non-zero; user may need to enable service after logging in.")
    except Exception as e:
        log.warning(f"[BATTERY] Could not run user systemctl commands: {e}")

# ----------------------
# Finalize: permissions + restart i3
# ----------------------
def set_executables_and_restart_i3():
    # set +x on ~/.config/i3/scripts, ~/.local/bin
    paths = [
        USER_HOME / ".config" / "i3" / "scripts",
        USER_HOME / ".local" / "bin"
    ]
    for p in paths:
        if p.exists() and p.is_dir():
            for f in p.rglob("*"):
                if f.is_file():
                    try:
                        if DRY_RUN:
                            log.info(f"[DRY-CHMOD] +x {f}")
                        else:
                            f.chmod(0o755)
                    except Exception:
                        pass
    # restart i3 if running for target user (best-effort, non-fatal)
    try:
        # check if i3 process is running for TARGET_USER
        p = run(["pgrep", "-u", TARGET_USER, "-x", "i3"], check=False, capture_output=True)
        rc = getattr(p, "returncode", 1)
        if rc == 0:
            log.info("[I3] i3 detected running; attempting restart via i3-msg (best-effort).")
            if DRY_RUN:
                log.info(f"[DRY-RUN] sudo -u {TARGET_USER} i3-msg restart")
            else:
                run(["sudo", "-u", TARGET_USER, "i3-msg", "restart"], check=False)
        else:
            log.info("[I3] i3 not detected for user; skipping restart to avoid breaking other DEs.")
    except Exception as e:
        log.warning(f"[WARN] i3 restart attempt failed: {e}")

# ----------------------
# Terminal profile tweaks (best-effort)
# ----------------------
def apply_terminal_profile_settings():
    snippet = r"""
PROFILE=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d \')
if [ -n "$PROFILE" ]; then
  gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE/" default-show-menubar false || true
  gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE/" font 'Monospace 9' || true
  gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE/" use-transparent-background true || true
  gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE/" background-transparency-percent 20 || true
fi
"""
    if DRY_RUN:
        log.info("[DRY-RUN] Would apply GNOME Terminal settings")
        return
    try:
        run(["sudo", "-u", TARGET_USER, "bash", "-lc", snippet], check=False)
    except Exception as e:
        log.warning(f"[WARN] Terminal profile settings failed: {e}")

# ----------------------
# GRUB theme apply + wallpaper mapping
# ----------------------
def apply_grub_theme(startup_dir: Path):
    log.info("[GRUB] Applying GRUB theme (best-effort).")
    repo_grub = startup_dir / "grub"
    dst_boot_grub = Path("/boot/grub/themes/kali")
    try:
        if dst_boot_grub.exists():
            if DRY_RUN:
                log.info(f"[DRY-RM] {dst_boot_grub}")
            else:
                shutil.rmtree(dst_boot_grub, ignore_errors=True)
        if repo_grub.exists():
            if DRY_RUN:
                log.info(f"[DRY-COPY] {repo_grub} -> {dst_boot_grub}")
            else:
                shutil.copytree(repo_grub, dst_boot_grub, dirs_exist_ok=True)
                log.info(f"[GRUB] Copied {repo_grub} -> {dst_boot_grub}")
        dst_usr = Path("/usr/share/grub/themes")
        ensure_dir(dst_usr)
        try:
            if not DRY_RUN:
                shutil.copytree(dst_boot_grub, dst_usr / "kali", dirs_exist_ok=True)
        except Exception:
            pass
    except Exception as e:
        log.warning(f"[WARN] Could not apply grub theme: {e}")

    # wallpapers already handled in copy_core_configs, but try mapping extra names if present
    repo_wall = startup_dir / "wallpaper"
    backgrounds_dir = Path("/usr/share/backgrounds/kali")
    ensure_dir(backgrounds_dir)
    mappings = [
        ("wallpaper-1.jpg", "login.svg"),
        ("wallpaper.jpg", "kali-maze-16x9.jpg"),
        ("wallpaper-2.jpg", "kali-tiles-16x9.jpg"),
        ("wallpaper-1.jpg", "kali-waves-16x9.png"),
        ("wallpaper.jpg", "kali-oleo-16x9.png"),
        ("wallpaper-2.jpg", "kali-tiles-purple-16x9.jpg"),
        ("wallpaper-1.jpg", "login-blurred"),
    ]
    for src_name, dst_name in mappings:
        s = repo_wall / src_name
        if s.exists():
            dst = backgrounds_dir / dst_name
            try:
                if dst.exists():
                    bak = dst.with_name(dst.name + f".{TIMESTAMP}.bak")
                    if DRY_RUN:
                        log.info(f"[DRY-Rename] {dst} -> {bak}")
                    else:
                        dst.rename(bak)
                        log.info(f"[SYS-RENAME] {dst} -> {bak}")
                if DRY_RUN:
                    log.info(f"[DRY-COPY] {s} -> {dst}")
                else:
                    shutil.copy2(s, dst)
                    log.info(f"[SYS-COPY] {s} -> {dst}")
            except Exception as e:
                log.warning(f"[WARN] Could not copy {s} -> {dst}: {e}")

# ----------------------
# App installers
# ----------------------
def install_telegram(startup_dir: Optional[Path] = None):
    log.info("[TELEGRAM] Installing Telegram desktop (best-effort).")
    tfile = Path("/tmp/tsetup.tar.xz")
    if DRY_RUN:
        log.info("[DRY-RUN] Would download Telegram to /tmp and extract to /opt/Telegram")
        return
    # download
    run(["wget", "-q", "https://telegram.org/dl/desktop/linux", "-O", str(tfile)], check=False)
    opt = Path("/opt/Telegram")
    if opt.exists():
        backup_existing(opt)
        try:
            shutil.rmtree(opt, ignore_errors=True)
        except Exception:
            pass
    ensure_dir(opt)
    # extract
    try:
        r = run(["tar", "-xf", str(tfile), "-C", str(opt), "--strip-components=1"], check=False)
    except Exception:
        r = None
    tbin = opt / "Telegram"
    if tbin.exists():
        try:
            tbin.chmod(0o755)
        except Exception:
            pass
        link = Path("/usr/local/bin/telegram")
        try:
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
        log.warning("[WARN] Telegram binary not found after extraction; please install manually.")

def install_brave_nightly():
    log.info("[BRAVE] Installing Brave nightly (best-effort).")
    if DRY_RUN:
        log.info("[DRY-RUN] Would run Brave install script")
        return
    # Running official installer script (best-effort)
    run('curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly bash', shell=True, check=False)
    run(["apt", "install", "-y", "brave-browser-nightly"], check=False)

def install_vscode():
    log.info("[VSCODE] Installing Visual Studio Code (.deb) (best-effort).")
    deb = Path("/tmp/code.deb")
    if DRY_RUN:
        log.info("[DRY-RUN] Would download VSCode .deb and install it")
        return
    run(["wget", "-q", "-O", str(deb),
         "https://update.code.visualstudio.com/latest/linux-deb-x64/stable"], check=False)
    if deb.exists():
        run(["dpkg", "-i", str(deb)], check=False)
        run(["apt", "install", "-f", "-y"], check=False)
        try:
            deb.unlink()
        except Exception:
            pass

def install_protonvpn():
    log.info("[PROTONVPN] Installing ProtonVPN (best-effort).")
    if DRY_RUN:
        log.info("[DRY-RUN] Would add ProtonVPN repo and install client")
        return
    deb = Path("/tmp/protonvpn.deb")
    url = "https://repo.protonvpn.com/debian/pool/main/p/protonvpn-cli/protonvpn-cli-stable.deb"
    run(["wget", "-q", url, "-O", str(deb)], check=False)
    if deb.exists():
        run(["dpkg", "-i", str(deb)], check=False)
        run(["apt", "update"], check=False)
        run(["apt", "install", "-f", "-y"], check=False)

def install_virtualbox():
    log.info("[VBOX] Installing VirtualBox (best-effort).")
    if DRY_RUN:
        log.info("[DRY-RUN] Would apt install virtualbox")
        return
    run(["apt", "update"], check=False)
    run(["apt", "install", "-y", "virtualbox"], check=False)

def install_rustscan():
    log.info("[RUSTSCAN] Installing RustScan (.deb) (best-effort).")
    deb = Path("/tmp/rustscan.deb")
    # Use the latest known simple URL pattern if available; keep best-effort
    url = "https://github.com/RustScan/RustScan/releases/latest/download/rustscan_amd64.deb"
    if DRY_RUN:
        log.info("[DRY-RUN] Would download RustScan and install")
        return
    run(["wget", "-q", url, "-O", str(deb)], check=False)
    if deb.exists():
        run(["dpkg", "-i", str(deb)], check=False)
        run(["apt", "install", "-f", "-y"], check=False)
        try:
            deb.unlink()
        except Exception:
            pass
    # Attempt to raise FD limit (best-effort)
    try:
        import resource
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        new_soft = max(soft, 4096)
        resource.setrlimit(resource.RLIMIT_NOFILE, (new_soft, hard))
        log.info(f"[ULIMIT] set RLIMIT_NOFILE soft={new_soft} hard={hard}")
    except Exception:
        pass

# ----------------------
# Interactive prompts
# ----------------------
def prompt_yes_no(prompt: str, default: str = "y") -> bool:
    default = default.lower()
    yn = "[Y/n]" if default == "y" else "[y/N]"
    try:
        while True:
            choice = input(f"{prompt} {yn}: ").strip().lower()
            if choice == "" and default:
                return default == "y"
            if choice in ("y", "yes"):
                return True
            if choice in ("n", "no"):
                return False
            print("Please answer 'y' or 'n'.")
    except KeyboardInterrupt:
        log.info("Interrupted by user; assuming 'no'.")
        return False

def prompt_multi_select() -> List[int]:
    lines = [
        "Select applications to install (enter numbers separated by spaces or commas):",
        " 1) Telegram",
        " 2) Brave (nightly)",
        " 3) Visual Studio Code",
        " 4) ProtonVPN",
        " 5) VirtualBox",
        " 6) RustScan",
        " 7) All",
        " 8) None",
    ]
    print("\n".join(lines))
    try:
        raw = input("Enter selection (e.g. '1 3 5' or '7' for All): ").strip()
    except KeyboardInterrupt:
        log.info("Interrupted by user; no apps selected.")
        return []
    if not raw:
        log.info("[INPUT] No selection entered; assuming 'None'.")
        return []
    tokens = []
    for part in raw.replace(",", " ").split():
        if part.isdigit():
            tokens.append(int(part))
        else:
            pl = part.lower()
            if pl in ("all", "7"):
                return list(range(1, 7))
            if pl in ("none", "0", "8"):
                return []
    if 7 in tokens:
        return list(range(1, 7))
    if 8 in tokens:
        return []
    return [t for t in tokens if 1 <= t <= 6]

# ----------------------
# Main flow
# ----------------------
def main():
    require_root()
    log.info("Starting startup_setup_full.py")
    startup_dir = detect_or_clone_repo()
    if not startup_dir.exists():
        log.warning("[WARN] startup repo directory does not exist; many steps may fail unless you place the repo here.")
    # Try apt installs first
    install_apt_packages(APT_PACKAGES)
    # Copy core configs (backups made)
    copy_core_configs(startup_dir)
    # Install battery monitor + try to enable
    install_battery_monitor(startup_dir)
    # Make scripts executable & restart i3 if running
    set_executables_and_restart_i3()
    # Terminal tweaks
    apply_terminal_profile_settings()
    # Ask about GRUB theme
    if prompt_yes_no("Do you want to apply GRUB theme (will copy grub/ assets to /boot and /usr/share)?", default="n"):
        apply_grub_theme(startup_dir)
    # App selection
    selections = prompt_multi_select()
    if not selections:
        log.info("[INFO] No applications selected for installation.")
    else:
        log.info(f"[INFO] Installing selected applications: {selections}")
        for sel in selections:
            if sel == 1:
                install_telegram(startup_dir)
            elif sel == 2:
                install_brave_nightly()
            elif sel == 3:
                install_vscode()
            elif sel == 4:
                install_protonvpn()
            elif sel == 5:
                install_virtualbox()
            elif sel == 6:
                install_rustscan()
    log.info("[DONE] Setup complete. Review log messages above for warnings and next steps.")
    log.info("If battery monitor or systemd --user steps failed, the user should enable/start the service after login:")
    log.info("  systemctl --user daemon-reload && systemctl --user enable --now battery-monitor.service")

if __name__ == "__main__":
    main()
