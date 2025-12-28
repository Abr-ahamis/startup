#!/usr/bin/env python3
"""
startup_setup_full.py

Simplified, hardened, and colorized upgrade:
- Always copy/apply grub theme (no prompt)
- Single Y/N prompt: install apps? (Telegram, Brave nightly, RustScan)
- Make i3 default (writes ~/.xinitrc + ~/.xsession and updates AccountsService if present)
- Short colored output lines listing the action and the files involved
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

# ----------------------------
# Config
# ----------------------------
REPO_URL = "https://github.com/Abr-ahamis/startup.git"
REPO_DIR_NAME = "startup"
DRY_RUN = False   # set True to simulate actions
TIMESTAMP = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")

APT_PACKAGES = [
    "i3-wm", "i3blocks", "rofi", "xdotool", "dex", "acpi", "upower",
    "xfce4-power-manager", "i3lock", "xss-lock", "pulseaudio-utils",
    "brightnessctl", "feh", "picom", "fonts-font-awesome", "git", "rsync",
    "unzip", "curl", "wget", "grub-customizer", "timeshift"
]

# ----------------------------
# Colors and small UI helpers
# ----------------------------
CSI = "\033["
RESET = CSI + "0m"
BOLD = CSI + "1m"
GREEN = CSI + "32m"
YELLOW = CSI + "33m"
RED = CSI + "31m"
CYAN = CSI + "36m"
MAG = CSI + "35m"

def cprint_ok(msg: str):
    print(f"{GREEN}[OK]{RESET} {msg}")

def cprint_info(msg: str):
    print(f"{CYAN}[INFO]{RESET} {msg}")

def cprint_warn(msg: str):
    print(f"{YELLOW}[WARN]{RESET} {msg}")

def cprint_err(msg: str):
    print(f"{RED}[ERROR]{RESET} {msg}")

# ----------------------------
# Basic environment detection
# ----------------------------
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

# ----------------------------
# Utility wrappers
# ----------------------------
def run(cmd, check: bool = False, capture_output: bool = True, shell: bool = False, env: Optional[dict] = None):
    if DRY_RUN:
        cprint_info(f"DRY-RUN CMD: {cmd}")
        class D: returncode = 0; stdout = ""; stderr = ""
        return D()
    if isinstance(cmd, (list, tuple)):
        cmd_display = " ".join(map(str, cmd))
    else:
        cmd_display = str(cmd)
    cprint_info(f"CMD: {cmd_display}")
    try:
        completed = subprocess.run(cmd, check=check, capture_output=capture_output, text=True, shell=shell, env=env)
        return completed
    except subprocess.CalledProcessError as e:
        cprint_warn(f"Command failed (rc={e.returncode}): {cmd_display}")
        return e

def ensure_dir(p: Path):
    if not p.exists():
        if DRY_RUN:
            cprint_info(f"DRY-MKDIR: {p}")
            return
        p.mkdir(parents=True, exist_ok=True)
        cprint_info(f"MKDIR: {p}")

def unique_backup_name(p: Path) -> Path:
    base = p.with_name(p.name + ".backup")
    if not base.exists():
        return base
    return p.with_name(p.name + f".backup.{TIMESTAMP}")

def backup_existing(path: Path) -> Optional[Path]:
    if not path.exists():
        return None
    bak = unique_backup_name(path)
    try:
        if DRY_RUN:
            cprint_info(f"DRY-BACKUP: {path} -> {bak}")
        else:
            shutil.move(str(path), str(bak))
            cprint_info(f"BACKUP: {path} -> {bak}")
        return bak
    except Exception as e:
        cprint_warn(f"Backup failed for {path}: {e}")
        return None

def safe_copy(src: Path, dst: Path, backup_if_exists: bool = True, dirs_exist_ok: bool = False) -> bool:
    if not src.exists():
        cprint_warn(f"SKIP (missing): {src}")
        return False
    ensure_dir(dst.parent)
    if dst.exists():
        if backup_if_exists:
            backup_existing(dst)
        else:
            if dst.is_dir():
                if not DRY_RUN:
                    shutil.rmtree(dst, ignore_errors=True)
            else:
                if not DRY_RUN:
                    dst.unlink()
    try:
        if src.is_dir():
            if DRY_RUN:
                cprint_info(f"DRY-COPY-DIR: {src} -> {dst}")
            else:
                shutil.copytree(src, dst, dirs_exist_ok=dirs_exist_ok)
                cprint_ok(f"COPY: {src} -> {dst}")
        else:
            if DRY_RUN:
                cprint_info(f"DRY-COPY-FILE: {src} -> {dst}")
            else:
                shutil.copy2(src, dst)
                cprint_ok(f"COPY: {src} -> {dst}")
        # attempt chown to target user where possible
        try:
            import pwd, os
            uid = pwd.getpwnam(TARGET_USER).pw_uid
            gid = pwd.getpwnam(TARGET_USER).pw_gid
            if not DRY_RUN:
                if dst.is_dir():
                    for root, _, files in os.walk(dst):
                        os.chown(root, uid, gid)
                        for f in files:
                            try:
                                os.chown(os.path.join(root, f), uid, gid)
                            except Exception:
                                pass
                else:
                    os.chown(str(dst), uid, gid)
        except Exception:
            pass
        return True
    except Exception as e:
        cprint_warn(f"Copy failed: {src} -> {dst}: {e}")
        return False

# ----------------------------
# Root check
# ----------------------------
def require_root():
    if os.geteuid() != 0:
        cprint_err("Run as root: sudo python3 startup_setup_full.py")
        sys.exit(1)

# ----------------------------
# Repo detection/clone
# ----------------------------
def detect_or_clone_repo() -> Path:
    cwd = Path.cwd()
    cprint_info(f"Working dir: {cwd}")
    if (cwd / "i3").is_dir() and (cwd / "grub").is_dir() and (cwd / "wallpaper").is_dir():
        cprint_info("Found startup files in current directory; using current dir as repo")
        return cwd
    if (cwd / REPO_DIR_NAME).is_dir():
        cprint_info(f"Found ./{REPO_DIR_NAME}; using it")
        return cwd / REPO_DIR_NAME
    target = cwd / REPO_DIR_NAME
    if DRY_RUN:
        cprint_info(f"DRY-RUN would clone {REPO_URL} -> {target}")
        return target
    if shutil.which("git") is None:
        cprint_warn("git missing; cannot clone. Place repo at ./startup")
        return target
    r = run(["git", "clone", "--depth", "1", REPO_URL, str(target)], capture_output=True)
    if getattr(r, "returncode", 1) != 0:
        cprint_warn("git clone returned non-zero; continuing (repo may exist locally).")
    return target

# ----------------------------
# Apt install (best-effort)
# ----------------------------
def install_apt_packages(packages: List[str]):
    if DRY_RUN:
        cprint_info(f"DRY-RUN apt install: {' '.join(packages)}")
        return
    if shutil.which("apt") is None:
        cprint_warn("apt not available; skipping package installation")
        return
    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    cprint_info("APT: update")
    run(["apt", "update"], capture_output=True, env=env)
    cprint_info(f"APT: install {len(packages)} pkgs")
    run(["apt", "install", "-y"] + packages, capture_output=True, env=env)

# ----------------------------
# Copy core configs and wallpapers
# ----------------------------
def copy_core_configs(startup_dir: Path):
    cprint_info("COPYING: repo -> user config (backups created if present)")
    repo_i3 = startup_dir / "i3"

    # single-file and directory targets (show short, clear output)
    safe_copy(repo_i3 / ".config" / "i3" / "config", USER_HOME / ".config" / "i3" / "config")
    safe_copy(repo_i3 / ".config" / "i3blocks", USER_HOME / ".config" / "i3blocks", dirs_exist_ok=True)
    safe_copy(repo_i3 / ".config" / "rofi", USER_HOME / ".config" / "rofi", dirs_exist_ok=True)
    safe_copy(repo_i3 / ".config" / "picom" / "picom.conf", USER_HOME / ".config" / "picom" / "picom.conf")

    # local bin
    src_local_bin = repo_i3 / ".local" / "bin"
    dst_local_bin = USER_HOME / ".local" / "bin"
    ensure_dir(dst_local_bin)
    if src_local_bin.exists():
        for f in sorted(src_local_bin.iterdir()):
            safe_copy(f, dst_local_bin / f.name)

    # fonts
    src_fonts = repo_i3 / ".local" / "share" / "fonts"
    dst_fonts = USER_HOME / ".local" / "share" / "fonts"
    ensure_dir(dst_fonts)
    if src_fonts.exists():
        for f in sorted(src_fonts.iterdir()):
            safe_copy(f, dst_fonts / f.name)

    # rofi system theme
    src_rofi_sys = repo_i3 / "usr" / "share" / "rofi" / "themes" / "Adapta-Nokto.rasi"
    dst_rofi_sys = Path("/usr/share/rofi/themes/Adapta-Nokto.rasi")
    if src_rofi_sys.exists():
        safe_copy(src_rofi_sys, dst_rofi_sys, backup_if_exists=True)

    # copy wallpapers to user Pictures and rotate system images (rename old)
    repo_wall = startup_dir / "wallpaper"
    ensure_dir(USER_HOME / "Pictures")
    for name in ("wallpaper.jpg", "wallpaper-1.jpg", "wallpaper-2.jpg"):
        s = repo_wall / name
        if s.exists():
            safe_copy(s, USER_HOME / "Pictures" / name)

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
            if DRY_RUN:
                cprint_info(f"DRY-Rename {dst} -> {bak}")
            else:
                try:
                    dst.rename(bak)
                    cprint_ok(f"SYS-RENAME: {dst} -> {bak}")
                except Exception as e:
                    cprint_warn(f"Could not rename {dst}: {e}")
        if s.exists():
            try:
                if DRY_RUN:
                    cprint_info(f"DRY SYS-COPY: {s} -> {dst}")
                else:
                    shutil.copy2(s, dst)
                    cprint_ok(f"SYS-COPY: {s} -> {dst}")
            except Exception as e:
                cprint_warn(f"Failed to copy {s} -> {dst}: {e}")

# ----------------------------
# Battery monitor install
# ----------------------------
def install_battery_monitor(startup_dir: Path):
    repo_script = startup_dir / "i3" / ".local" / "bin" / "battery-monitor.sh"
    repo_service = startup_dir / "i3" / ".config" / "systemd" / "user" / "battery-monitor.service"
    dst_script = USER_HOME / ".local" / "bin" / "battery-monitor.sh"
    dst_service = USER_HOME / ".config" / "systemd" / "user" / "battery-monitor.service"

    if repo_script.exists():
        ensure_dir(dst_script.parent)
        safe_copy(repo_script, dst_script)
        if not DRY_RUN:
            try:
                dst_script.chmod(0o755)
            except Exception:
                pass
            cprint_ok(f"COPY: {repo_script} -> {dst_script}")
    if repo_service.exists():
        ensure_dir(dst_service.parent)
        safe_copy(repo_service, dst_service)
        cprint_ok(f"COPY: {repo_service} -> {dst_service}")

    # attempt systemctl --user enable/now as the target user (best-effort)
    try:
        uid = pwd.getpwnam(TARGET_USER).pw_uid
        cmd = (
            f"XDG_RUNTIME_DIR=/run/user/{uid} systemctl --user daemon-reload && "
            f"XDG_RUNTIME_DIR=/run/user/{uid} systemctl --user enable --now battery-monitor.service"
        )
        if DRY_RUN:
            cprint_info(f"DRY-RUN: would run (as {TARGET_USER}): {cmd}")
        else:
            r = run(["sudo", "-u", TARGET_USER, "bash", "-lc", cmd], capture_output=True)
            if getattr(r, "returncode", 1) == 0:
                cprint_ok("BATTERY: systemctl --user reload/enable attempted")
            else:
                cprint_warn("BATTERY: systemctl --user returned non-zero; user may need to enable after login")
    except Exception as e:
        cprint_warn(f"BATTERY: failed to run user systemctl: {e}")

# ----------------------------
# GRUB theme apply (always run)
# ----------------------------
def apply_grub_theme(startup_dir: Path):
    cprint_info("Applying GRUB theme (no prompt)")
    repo_grub = startup_dir / "grub"
    dst_boot = Path("/boot/grub/themes/kali")
    dst_usr = Path("/usr/share/grub/themes")
    ensure_dir(dst_boot)
    ensure_dir(dst_usr)
    if repo_grub.exists():
        # copy to /boot and /usr/share
        try:
            if DRY_RUN:
                cprint_info(f"DRY-COPY {repo_grub} -> {dst_boot}")
            else:
                if dst_boot.exists():
                    shutil.rmtree(dst_boot, ignore_errors=True)
                shutil.copytree(repo_grub, dst_boot, dirs_exist_ok=True)
                cprint_ok(f"COPY: {repo_grub} -> {dst_boot}")
        except Exception as e:
            cprint_warn(f"GRUB copy to /boot failed: {e}")
        try:
            if DRY_RUN:
                cprint_info(f"DRY-COPY {repo_grub} -> {dst_usr}/kali")
            else:
                shutil.copytree(repo_grub, dst_usr / "kali", dirs_exist_ok=True)
                cprint_ok(f"COPY: {repo_grub} -> {dst_usr}/kali")
        except Exception as e:
            cprint_warn(f"GRUB copy to /usr/share failed: {e}")
    else:
        cprint_warn("No grub/ directory found in repo; skipping grub theme copy")

# ----------------------------
# App installers (Telegram, Brave, RustScan)
# ----------------------------
def install_telegram(startup_dir: Optional[Path] = None):
    cprint_info("Installing Telegram (best-effort)")
    tfile = Path("/tmp/tsetup.tar.xz")
    if DRY_RUN:
        cprint_info("DRY-RUN: would download + extract telegram and symlink /usr/local/bin/telegram")
        return
    run(["wget", "-q", "https://telegram.org/dl/desktop/linux", "-O", str(tfile)])
    opt = Path("/opt/Telegram")
    if opt.exists():
        backup_existing(opt)
        shutil.rmtree(opt, ignore_errors=True)
    ensure_dir(opt)
    run(["tar", "-xf", str(tfile), "-C", str(opt), "--strip-components=1"])
    tbin = opt / "Telegram"
    if tbin.exists():
        try:
            tbin.chmod(0o755)
        except Exception:
            pass
        link = Path("/usr/local/bin/telegram")
        if link.exists() or link.is_symlink():
            try:
                link.unlink()
            except Exception:
                pass
        try:
            link.symlink_to(tbin)
            cprint_ok(f"SYMLINK: /usr/local/bin/telegram -> {tbin}")
        except Exception as e:
            cprint_warn(f"Could not create symlink /usr/local/bin/telegram: {e}")
    else:
        cprint_warn("Telegram binary not found after extract")

def install_brave_nightly():
    cprint_info("Installing Brave (nightly) (best-effort)")
    if DRY_RUN:
        cprint_info("DRY-RUN: would run Brave installer script + apt install brave-browser-nightly")
        return
    run('curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly bash', shell=True)
    run(["apt", "install", "-y", "brave-browser-nightly"])

def install_rustscan():
    cprint_info("Installing RustScan (best-effort)")
    deb = Path("/tmp/rustscan.deb")
    url = "https://github.com/RustScan/RustScan/releases/latest/download/rustscan_amd64.deb"
    if DRY_RUN:
        cprint_info("DRY-RUN: would download rustscan .deb and dpkg -i")
        return
    run(["wget", "-q", url, "-O", str(deb)])
    if deb.exists():
        run(["dpkg", "-i", str(deb)])
        run(["apt", "install", "-f", "-y"])

# ----------------------------
# Make i3 default: write ~/.xinitrc and ~/.xsession and attempt AccountsService update
# ----------------------------
def set_i3_default():
    cprint_info("Setting i3 as default session for next login (writes ~/.xinitrc and ~/.xsession)")
    xinit = USER_HOME / ".xinitrc"
    xsession = USER_HOME / ".xsession"
    content = "exec i3\n"

    for p in (xinit, xsession):
        if p.exists():
            backup_existing(p)
        if DRY_RUN:
            cprint_info(f"DRY-RUN: would write {p} with 'exec i3'")
        else:
            try:
                p.write_text(content)
                p.chmod(0o644)
                cprint_ok(f"WRITE: {p} -> exec i3")
            except Exception as e:
                cprint_warn(f"Could not write {p}: {e}")

    # Try to update AccountsService (used by GDM/LightDM) to set XSession=i3
    acct_path = Path("/var/lib/AccountsService/users") / TARGET_USER
    if acct_path.exists():
        try:
            backup_existing(acct_path)
            txt = acct_path.read_text()
            if "XSession=" in txt:
                txt = "\n".join([line if not line.startswith("XSession=") else "XSession=i3" for line in txt.splitlines()])
            else:
                txt = txt + "\nXSession=i3\n"
            if DRY_RUN:
                cprint_info(f"DRY-RUN: would update {acct_path} to set XSession=i3")
            else:
                acct_path.write_text(txt)
                cprint_ok(f"MODIFY: {acct_path} -> XSession=i3")
        except Exception as e:
            cprint_warn(f"AccountsService update failed: {e}")
    else:
        cprint_info("AccountsService entry not present; user may need to choose i3 at login once.")

    # Inform user how to make sure DM uses .xsession if needed
    cprint_info("After reboot/login the display manager may still choose sessions; ensure you select 'i3' once from greeter if needed.")

# ----------------------------
# Simple Y/N prompt
# ----------------------------
def prompt_yes_no(question: str, default: bool = False) -> bool:
    yes_choices = {"y", "yes"}
    no_choices = {"n", "no"}
    default_str = "Y/n" if default else "y/N"
    try:
        while True:
            ans = input(f"{BOLD}{question} [{default_str}]: {RESET}").strip().lower()
            if ans == "" and default:
                return True
            if ans == "" and not default:
                return False
            if ans in yes_choices:
                return True
            if ans in no_choices:
                return False
            print("Please answer y or n.")
    except KeyboardInterrupt:
        cprint_warn("Interrupted; assuming 'no'")
        return False

# ----------------------------
# Main flow
# ----------------------------
def main():
    require_root()
    cprint_info(f"Target user: {TARGET_USER}, home: {USER_HOME}")
    startup_dir = detect_or_clone_repo()
    if not startup_dir.exists():
        cprint_warn("Startup repo directory does not exist; many steps may be no-op unless you place the repo.")
    # install apt packages (best-effort)
    install_apt_packages(APT_PACKAGES)
    # copy configs and wallpapers
    copy_core_configs(startup_dir)
    # install battery monitor (if present)
    install_battery_monitor(startup_dir)
    # always apply grub theme
    apply_grub_theme(startup_dir)
    # make executables + restart i3 if running
    set_executables_and_restart_i3()
    # apply terminal tweaks (best-effort)
    # (kept from earlier implementations, best-effort, skip complex output)
    # ask single y/n: install apps?
    if prompt_yes_no("Install Telegram, Brave (nightly) and RustScan now?", default=False):
        install_telegram(startup_dir)
        install_brave_nightly()
        install_rustscan()
    else:
        cprint_info("Skipping app installations.")
    # set i3 default for next login
    set_i3_default()
    cprint_ok("Setup complete — check above lines for actions and file paths changed.")

# ----------------------------
# helpers: detect_or_clone_repo + other functions used above
# ----------------------------
def detect_or_clone_repo() -> Path:
    cwd = Path.cwd()
    if (cwd / "i3").is_dir() and (cwd / "grub").is_dir() and (cwd / "wallpaper").is_dir():
        return cwd
    if (cwd / REPO_DIR_NAME).is_dir():
        return cwd / REPO_DIR_NAME
    target = cwd / REPO_DIR_NAME
    if DRY_RUN:
        return target
    if shutil.which("git") is None:
        cprint_warn("git not found; cannot clone.")
        return target
    r = run(["git", "clone", "--depth", "1", REPO_URL, str(target)], capture_output=True)
    if getattr(r, "returncode", 1) != 0:
        cprint_warn("git clone returned non-zero; continuing anyway.")
    return target

def install_apt_packages(packages: List[str]):
    if DRY_RUN:
        cprint_info(f"DRY-RUN apt install: {' '.join(packages)}")
        return
    if shutil.which("apt") is None:
        cprint_warn("apt not found; skipping package installation")
        return
    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    run(["apt", "update"], capture_output=True, env=env)
    run(["apt", "install", "-y"] + packages, capture_output=True, env=env)

def set_executables_and_restart_i3():
    # chmod +x for scripts
    for p in (USER_HOME / ".config" / "i3" / "scripts", USER_HOME / ".local" / "bin"):
        if p.exists():
            for f in p.rglob("*"):
                if f.is_file():
                    try:
                        if not DRY_RUN:
                            f.chmod(0o755)
                    except Exception:
                        pass
    # restart i3 if running
    p = run(["pgrep", "-u", TARGET_USER, "-x", "i3"], capture_output=True)
    if getattr(p, "returncode", 1) == 0:
        if DRY_RUN:
            cprint_info("DRY-RUN: would restart i3 (i3-msg restart)")
        else:
            run(["sudo", "-u", TARGET_USER, "i3-msg", "restart"])

# ----------------------------
# ensure require_root function defined here (was above)
# ----------------------------
def require_root():
    if os.geteuid() != 0:
        cprint_err("Please run as root (sudo python3 startup_setup_full.py)")
        sys.exit(1)

# ----------------------------
# Entrypoint
# ----------------------------
if __name__ == "__main__":
    main()
