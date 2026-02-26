#!/usr/bin/env python3
"""
startup_best.py

Unified, robust setup script derived from main.py, startup.py, and startup2.py.
Focus:
- Consistent backups to ~/.BACKUPDV
- Safer apt handling (locks, retries, repair)
- Reliable package detection
- Clear logging + concise output
- Battery monitor install with systemctl --user reliability
- GRUB theme applied safely
- Optional app install menu

Use --dry-run to preview without changes.
"""
from __future__ import annotations

import datetime
import os
import pwd
import shutil
import subprocess
import sys
import termios
import tty
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# =========================
# Configuration Flags (bash-style)
# =========================
DRY_RUN = True       # Set to True to preview without making changes
NO_MENU = True       # Set to True to skip optional apps menu
CLEAR_SCREEN = False # Set to True to clear screen during menu
REPO_URL = "https://github.com/Abr-ahamis/startup.git"
REPO_DIR_NAME = "startup"
BACKUP_ROOT_NAME = ".BACKUPDV"
TIMESTAMP = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")

APT_PACKAGES = [
    "i3", "i3-wm", "i3blocks", "rofi", "xdotool", "dex", "acpi", "upower",
    "xfce4-power-manager", "i3lock", "xss-lock", "pulseaudio-utils",
    "brightnessctl", "feh", "picom", "fonts-font-awesome", "git", "rsync",
    "unzip", "ruby-notify", "curl", "wget", "grub-customizer", "timeshift", "redshift",
]

OPTIONAL_APPS = ["Telegram", "Brave (Nightly)", "RustScan"]

PKG_CMD_MAP: Dict[str, str] = {
    "i3": "i3",
    "i3-wm": "i3",
    "i3blocks": "i3blocks",
    "rofi": "rofi",
    "picom": "picom",
    "feh": "feh",
    "redshift": "redshift",
    "curl": "curl",
    "wget": "wget",
    "git": "git",
    "rsync": "rsync",
    "unzip": "unzip",
}

# =========================
# UI helpers
# =========================
CSI = "\033["
RESET = CSI + "0m"
BOLD = CSI + "1m"
GREEN = CSI + "32m"
YELLOW = CSI + "33m"
RED = CSI + "31m"
CYAN = CSI + "36m"

CHECK = "✔"
CROSS = "✖"
ARROW = "➜"


def _c(s: str, col: str) -> str:
    return f"{col}{s}{RESET}"


def ok(s: str) -> str:
    return _c(s, GREEN)


def warn(s: str) -> str:
    return _c(s, YELLOW)


def err(s: str) -> str:
    return _c(s, RED)


def info(s: str) -> str:
    return _c(s, CYAN)


def header(target_user: str) -> None:
    print()
    print("╔" + "═" * 50 + "╗")
    print("║" + "{:^50}".format("Walcome back Sr.") + "║")
    print("╚" + "═" * 50 + "╝")
    print(f"👤 Target User  : {target_user}")
    print("⚙️  Mode         : Full Environment Setup")
    print("🚀 Starting setup...\n")


def section(title: str) -> None:
    print("──────────────────────────────────────────────")
    print(title)
    print("──────────────────────────────────────────────")


def progress_bar(current: int, total: int, width: int = 24) -> str:
    frac = current / total if total else 1.0
    filled = int(frac * width)
    bar = "█" * filled + "░" * (width - filled)
    pct = int(frac * 100)
    return f"{bar} {pct}%"

# =========================
# Environment
# =========================

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

BACKUP_ROOT = USER_HOME / BACKUP_ROOT_NAME
DEFAULT_LOG = USER_HOME / ".startup_install.log"

# =========================
# Utilities
# =========================

def run(cmd, check: bool = False, capture_output: bool = True, shell: bool = False, env: Optional[dict] = None) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, check=check, capture_output=capture_output, text=True, shell=shell, env=env)


def log_line(log_path: Path, message: str) -> None:
    try:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("a", encoding="utf-8") as f:
            f.write(message + "\n")
    except Exception:
        pass


def ensure_dir(p: Path, dry_run: bool) -> None:
    if not p.exists() and not dry_run:
        p.mkdir(parents=True, exist_ok=True)


def backup_to_backupdv(dst: Path, dry_run: bool) -> Optional[Path]:
    if not dst.exists():
        return None
    try:
        if str(dst).startswith(str(USER_HOME)):
            rel = dst.relative_to(USER_HOME)
            target = BACKUP_ROOT / rel
        else:
            rel = Path(dst.as_posix().lstrip("/"))
            target = BACKUP_ROOT / "root" / rel
        ensure_dir(target.parent, dry_run)
        if target.exists():
            target = target.with_name(target.name + f".backup.{TIMESTAMP}")
        if not dry_run:
            shutil.move(str(dst), str(target))
        return target
    except Exception:
        return None


def safe_copy(src: Path, dst: Path, dry_run: bool, dirs_exist_ok: bool = False) -> bool:
    if not src.exists():
        return False
    ensure_dir(dst.parent, dry_run)
    if dst.exists():
        backup_to_backupdv(dst, dry_run)
    try:
        if src.is_dir():
            if not dry_run:
                shutil.copytree(src, dst, dirs_exist_ok=dirs_exist_ok)
        else:
            if not dry_run:
                # atomic-ish replace for files
                tmp = dst.with_name(dst.name + ".tmp")
                shutil.copy2(src, tmp)
                os.replace(tmp, dst)
        return True
    except Exception:
        return False


def is_pkg_installed(pkg: str, dry_run: bool) -> bool:
    if dry_run:
        return False
    cmd = PKG_CMD_MAP.get(pkg)
    if cmd and shutil.which(cmd):
        return True
    cp = subprocess.run(
        ["dpkg-query", "-W", "-f=${Status}", pkg],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    return cp.stdout.strip() == "install ok installed"


def wait_for_apt_lock(timeout_s: int, dry_run: bool) -> bool:
    if dry_run:
        return True
    for _ in range(timeout_s):
        lock_busy = subprocess.run(["fuser", "/var/lib/dpkg/lock-frontend"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        apt_busy = subprocess.run(["pgrep", "-x", "apt"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        dpkg_busy = subprocess.run(["pgrep", "-x", "dpkg"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if lock_busy.returncode != 0 and apt_busy.returncode != 0 and dpkg_busy.returncode != 0:
            return True
        time.sleep(1)
    return False


def apt_install_packages(packages: List[str], log_path: Path, dry_run: bool) -> bool:
    if dry_run:
        return True
    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    env["APT_LISTCHANGES_FRONTEND"] = "none"

    if not wait_for_apt_lock(30, dry_run=False):
        log_line(log_path, "apt lock timeout")
        return False

    run(["apt-get", "update", "-y"], env=env)
    cp = run(["apt-get", "install", "-y"] + packages, env=env)
    if cp.returncode == 0:
        return True

    log_line(log_path, f"apt install failed: {cp.stderr or cp.stdout}")

    # repair attempts
    run(["apt-get", "-f", "install", "-y"], env=env)
    run(["dpkg", "--configure", "-a"], env=env)
    run(["apt-get", "update", "-y"], env=env)

    cp2 = run(["apt-get", "install", "-y"] + packages, env=env)
    if cp2.returncode == 0:
        return True

    log_line(log_path, f"apt retry failed: {cp2.stderr or cp2.stdout}")
    return False


# =========================
# Repo
# =========================

def detect_or_clone_repo(dry_run: bool) -> Path:
    cwd = Path.cwd()
    if (cwd / "i3").is_dir() and (cwd / "grub").is_dir() and (cwd / "wallpaper").is_dir():
        return cwd
    if (cwd / REPO_DIR_NAME).is_dir():
        return cwd / REPO_DIR_NAME
    target = cwd / REPO_DIR_NAME
    if dry_run:
        return target
    if shutil.which("git") is None:
        return target
    run(["git", "clone", "--depth", "1", REPO_URL, str(target)])
    return target

# =========================
# Core steps
# =========================

def install_packages(log_path: Path, dry_run: bool) -> None:
    section("📦 PACKAGE INSTALLATION SECTION")
    missing = [p for p in APT_PACKAGES if not is_pkg_installed(p, dry_run)]

    if not missing:
        for pkg in APT_PACKAGES:
            print(ok(f"[{CHECK}] {pkg:<18} already installed"))
        return

    for pkg in APT_PACKAGES:
        if is_pkg_installed(pkg, dry_run):
            print(ok(f"[{CHECK}] {pkg:<18} already installed"))

    print(info(f"Missing packages: {', '.join(missing)}"))
    if not apt_install_packages(missing, log_path, dry_run):
        print(warn("[✖] apt install failed; see log for details"))
    else:
        print(ok("✅ All packages verified."))


def copy_configs_and_wallpapers(startup_dir: Path, dry_run: bool) -> None:
    section("📁 CONFIG DEPLOYMENT SECTION")

    repo_i3 = startup_dir / "i3"
    success = {
        "i3": safe_copy(repo_i3 / ".config" / "i3" / "config", USER_HOME / ".config" / "i3" / "config", dry_run),
        "i3blocks": safe_copy(repo_i3 / ".config" / "i3blocks", USER_HOME / ".config" / "i3blocks", dry_run, dirs_exist_ok=True),
        "rofi": safe_copy(repo_i3 / ".config" / "rofi", USER_HOME / ".config" / "rofi", dry_run, dirs_exist_ok=True),
        "picom": safe_copy(repo_i3 / ".config" / "picom" / "picom.conf", USER_HOME / ".config" / "picom" / "picom.conf", dry_run),
    }

    safe_copy(
        repo_i3 / ".config" / "i3" / "scripts" / "terminal-font.sh",
        USER_HOME / ".config" / "i3" / "scripts" / "terminal-font.sh",
        dry_run,
    )

    src_local_bin = repo_i3 / ".local" / "bin"
    dst_local_bin = USER_HOME / ".local" / "bin"
    ensure_dir(dst_local_bin, dry_run)
    if src_local_bin.exists():
        for f in sorted(src_local_bin.iterdir()):
            safe_copy(f, dst_local_bin / f.name, dry_run)

    src_fonts = repo_i3 / ".local" / "share" / "fonts"
    dst_fonts = USER_HOME / ".local" / "share" / "fonts"
    ensure_dir(dst_fonts, dry_run)
    font_count = 0
    if src_fonts.exists():
        for f in sorted(src_fonts.iterdir()):
            if safe_copy(f, dst_fonts / f.name, dry_run):
                font_count += 1

    src_rofi = repo_i3 / "usr" / "share" / "rofi" / "themes" / "Adapta-Nokto.rasi"
    if src_rofi.exists():
        safe_copy(src_rofi, Path("/usr/share/rofi/themes/Adapta-Nokto.rasi"), dry_run)

    print(ok("[✔] i3 config updated") if success["i3"] else warn("[✖] i3 config update failed"))
    print(ok("[✔] i3blocks config updated") if success["i3blocks"] else warn("[✖] i3blocks update failed"))
    print(ok("[✔] rofi theme applied") if success["rofi"] else warn("[✖] rofi update failed"))
    print(ok("[✔] picom configuration updated") if success["picom"] else warn("[✖] picom update failed"))
    print(ok(f"[✔] Fonts installed ({font_count})"))

    section("🖼 WALLPAPER SECTION")
    repo_wall = startup_dir / "wallpaper"
    ensure_dir(USER_HOME / "Pictures", dry_run)
    for name in ("wallpaper.jpg", "wallpaper-1.jpg", "wallpaper-2.jpg"):
        s = repo_wall / name
        if s.exists():
            safe_copy(s, USER_HOME / "Pictures" / name, dry_run)

    backgrounds_dir = Path("/usr/share/backgrounds/kali")
    ensure_dir(backgrounds_dir, dry_run)

    targets = [
        "kali-maze-16x9.jpg",
        "kali-oleo-16x9.png",
        "kali-tiles-purple-16x9.jpg",
        "kali-tiles-16x9.jpg",
        "kali-waves-16x9.png",
        "login.svg",
        "login-blurred",
    ]
    sources = [repo_wall / "wallpaper-1.jpg", repo_wall / "wallpaper.jpg"]
    replaced = 0
    for i, name in enumerate(targets):
        src = sources[i % len(sources)]
        dst = backgrounds_dir / name
        if not src.exists():
            continue
        if dst.exists():
            backup_to_backupdv(dst, dry_run)
        try:
            if not dry_run:
                shutil.copy2(src, dst)
            replaced += 1
        except Exception:
            pass

    print(ok(f"[✔] Wallpapers replaced ({replaced})"))
    print(ok("wallpaper are replaced"))

    i3_wallpaper = backgrounds_dir / "wallpaper-1.jpg"
    src_i3 = repo_wall / "wallpaper-1.jpg"
    if src_i3.exists():
        if not i3_wallpaper.exists():
            safe_copy(src_i3, i3_wallpaper, dry_run)
        print(ok("i3 wallpaper set"))


def install_battery_monitor(startup_dir: Path, log_path: Path, dry_run: bool) -> List[Tuple[str, bool, str]]:
    section("🔋 BATTERY MONITOR SETUP")
    repo_script = startup_dir / "i3" / ".local" / "bin" / "battery-monitor.sh"
    repo_service = startup_dir / "i3" / ".config" / "systemd" / "user" / "battery-monitor.service"
    dst_script = USER_HOME / ".local" / "bin" / "battery-monitor.sh"
    dst_service = USER_HOME / ".config" / "systemd" / "user" / "battery-monitor.service"

    results: List[Tuple[str, bool, str]] = []

    if repo_script.exists():
        safe_copy(repo_script, dst_script, dry_run)
        if not dry_run:
            try:
                dst_script.chmod(0o755)
                results.append((f"chmod +x {dst_script}", True, "ok"))
            except Exception as e:
                results.append((f"chmod +x {dst_script}", False, str(e)))
    else:
        results.append((f"chmod +x {dst_script}", False, "script missing"))

    if repo_service.exists():
        safe_copy(repo_service, dst_service, dry_run)
        results.append((f"copy {repo_service} -> {dst_service}", True, "ok"))
    else:
        results.append((f"copy {repo_service} -> {dst_service}", False, "service missing"))

    # systemctl --user as target user
    try:
        uid = pwd.getpwnam(TARGET_USER).pw_uid
        runtime_dir = f"/run/user/{uid}"
        if not dry_run and not Path(runtime_dir).exists():
            # Try enable linger so user services can run without login
            run(["loginctl", "enable-linger", TARGET_USER])

        def run_user_systemctl(args: str) -> Tuple[bool, str]:
            full = f"XDG_RUNTIME_DIR={runtime_dir} systemctl --user {args}"
            if dry_run:
                return True, "dry-run"
            cp = run(["sudo", "-u", TARGET_USER, "bash", "-lc", full])
            ok_ = cp.returncode == 0
            brief = (cp.stdout or cp.stderr or "").strip()
            return ok_, brief

        ok1, br1 = run_user_systemctl("daemon-reload")
        results.append(("systemctl --user daemon-reload", ok1, br1))
        ok2, br2 = run_user_systemctl("enable --now battery-monitor.service")
        results.append(("systemctl --user enable --now battery-monitor.service", ok2, br2))
        if not ok2:
            ok3, br3 = run_user_systemctl("start battery-monitor.service")
            results.append(("systemctl --user start battery-monitor.service", ok3, br3))
    except Exception as e:
        log_line(log_path, f"battery systemctl failed: {e}")

    print(ok("battery-monitor setuped"))
    return results


def apply_grub_theme(startup_dir: Path, dry_run: bool) -> None:
    section("🎨 GRUB THEME SETUP")
    repo_grub = startup_dir / "grub"
    dst_boot = Path("/boot/grub/themes/kali")
    dst_usr = Path("/usr/share/grub/themes/kali")
    if not repo_grub.exists():
        print(warn("No grub/ directory found; skipping"))
        return

    if dst_boot.exists():
        backup_to_backupdv(dst_boot, dry_run)
    if dst_usr.exists():
        backup_to_backupdv(dst_usr, dry_run)

    try:
        if not dry_run:
            shutil.copytree(repo_grub, dst_boot, dirs_exist_ok=True)
            shutil.copytree(repo_grub, dst_usr, dirs_exist_ok=True)
        print(ok("grub setuped"))
    except Exception:
        print(warn("grub copy failed"))

    # timeout change directly in grub.cfg (set timeout=2)
    grub_cfg = Path("/boot/grub/grub.cfg")
    if grub_cfg.exists() and not dry_run:
        try:
            # Copy backup only; do not move/rename grub.cfg
            backup_dir = BACKUP_ROOT / "root" / "boot" / "grub"
            ensure_dir(backup_dir, dry_run)
            backup_path = backup_dir / f"grub.cfg.backup.{TIMESTAMP}"
            shutil.copy2(grub_cfg, backup_path)
            run(["sed", "-i", "-E", r"s/^[[:space:]]*set timeout=(30|5)/  set timeout=2/", str(grub_cfg)])
            print(ok("grub timeout set to 2s in grub.cfg"))
        except Exception:
            print(warn("grub timeout update failed"))




def make_scripts_executable(dry_run: bool) -> None:
    for p in (
        USER_HOME / ".config" / "i3" / "scripts",
        USER_HOME / ".local" / "bin",
        USER_HOME / ".config" / "i3blocks" / "scripts",
    ):
        if p.exists():
            for f in p.rglob("*"):
                if f.is_file():
                    try:
                        if not dry_run:
                            f.chmod(0o755)
                    except Exception:
                        pass

# =========================
# Optional apps
# =========================

def read_key() -> str:
    if not sys.stdin.isatty():
        return ""
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        ch = os.read(fd, 3)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
    return ch.decode(errors="ignore")


def select_menu(options: List[str], no_clear: bool) -> List[bool]:
    selected = [False] * len(options)
    cursor = 0

    if not sys.stdin.isatty():
        return selected

    while True:
        if not no_clear:
            os.system("clear")
        header(TARGET_USER)
        print("Install Telegram, Brave and RustScan now?\n")
        for i, opt in enumerate(options):
            prefix = ">" if i == cursor else " "
            box = "[*]" if selected[i] else "[ ]"
            print(f" {prefix} {box} {opt}")
        print("\n(Use arrows to move, Space/Enter to toggle, 'f' when finished)")
        key = read_key()
        if key in ("\x1b[A", "\x1bOA"):
            cursor = (cursor - 1) % len(options)
        elif key in ("\x1b[B", "\x1bOB"):
            cursor = (cursor + 1) % len(options)
        elif key in (" ", "\r", "\n"):
            selected[cursor] = not selected[cursor]
        elif key == "f":
            break

    return selected


def download(url: str, dest: Path, dry_run: bool) -> bool:
    if dry_run:
        return True
    if shutil.which("curl"):
        cp = run(["curl", "-fL", "--retry", "3", "--retry-delay", "5", url, "-o", str(dest)])
        return cp.returncode == 0 and dest.exists() and dest.stat().st_size > 0
    if shutil.which("wget"):
        cp = run(["wget", "--tries=3", "--wait=3", "-O", str(dest), url])
        return cp.returncode == 0 and dest.exists() and dest.stat().st_size > 0
    return False


def install_telegram(dry_run: bool) -> None:
    if shutil.which("telegram") or shutil.which("telegram-desktop") or Path("/usr/local/bin/telegram").exists():
        print(ok("[✔] Telegram already installed"))
        return
    print(ok("[➜] Telegram installing..."))
    tfile = Path("/tmp/tsetup.tar.xz")
    if not download("https://telegram.org/dl/desktop/linux", tfile, dry_run):
        print(warn("[✖] Telegram download failed"))
        return
    opt = Path("/opt/Telegram")
    if opt.exists():
        backup_to_backupdv(opt, dry_run)
    ensure_dir(opt, dry_run)
    if not dry_run:
        run(["tar", "-xf", str(tfile), "-C", str(opt), "--strip-components=1"])
    tbin = opt / "Telegram"
    if tbin.exists() or dry_run:
        if not dry_run:
            try:
                tbin.chmod(0o755)
            except Exception:
                pass
        link = Path("/usr/local/bin/telegram")
        if link.exists() or link.is_symlink():
            backup_to_backupdv(link, dry_run)
        try:
            if not dry_run:
                link.symlink_to(tbin)
            print(ok("[✔] Telegram installed"))
        except Exception:
            print(warn("[✖] Telegram installation failed"))


def install_brave(dry_run: bool) -> None:
    if shutil.which("brave-browser") or shutil.which("brave-browser-nightly"):
        print(ok("[✔] Brave already installed"))
        return
    print(ok("[➜] Brave (Nightly) installing..."))
    if dry_run:
        return
    run("curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly sh", shell=True)
    run(["apt", "install", "-y", "brave-browser-nightly"])
    print(ok("[✔] Brave installed"))


def install_rustscan(dry_run: bool) -> None:
    if shutil.which("rustscan"):
        print(ok("[✔] RustScan already installed"))
        return
    print(ok("[➜] RustScan installing..."))
    deb = Path("/tmp/rustscan_amd64.deb")
    url = "https://github.com/bee-san/RustScan/releases/download/2.4.1/rustscan.deb.zip"
    if not download(url, deb, dry_run):
        print(warn("[✖] RustScan download failed"))
        return
    if not dry_run:
        run(["dpkg", "-i", str(deb)])
        run(["apt", "install", "-f", "-y"])
    print(ok("[✔] RustScan installed"))

# =========================
# i3 default and restart
# =========================

def set_i3_default(dry_run: bool) -> None:
    section("🖥️  I3 DEFAULT SESSION SETUP")
    xinit = USER_HOME / ".xinitrc"
    xsession = USER_HOME / ".xsession"
    content = "exec i3\n"
    for p in (xinit, xsession):
        if p.exists():
            backup_to_backupdv(p, dry_run)
        if not dry_run:
            try:
                p.write_text(content)
                p.chmod(0o644)
            except Exception:
                pass

    acct = Path("/var/lib/AccountsService/users") / TARGET_USER
    if acct.exists():
        try:
            txt = acct.read_text()
            if "XSession=" in txt:
                txt = "\n".join([line if not line.startswith("XSession=") else "XSession=i3" for line in txt.splitlines()])
            else:
                txt = txt + "\nXSession=i3\n"
            backup_to_backupdv(acct, dry_run)
            if not dry_run:
                acct.write_text(txt)
            print(ok("i3 set as default (AccountsService updated)"))
        except Exception:
            print(warn("AccountsService update failed"))

    if not dry_run:
        run(["update-alternatives", "--install", "/usr/bin/x-session-manager", "x-session-manager", "/usr/bin/i3", "60"])
        run(["update-alternatives", "--set", "x-session-manager", "/usr/bin/i3"])


def restart_i3_or_prompt(dry_run: bool) -> None:
    p = run(["pgrep", "-u", TARGET_USER, "-x", "i3"])
    if getattr(p, "returncode", 1) == 0:
        if not dry_run:
            run(["sudo", "-u", TARGET_USER, "i3-msg", "restart"])
        print(ok("i3 restarted"))
    else:
        if not dry_run:
            try:
                ans = input("Restart now to apply session manager change? [y/N]: ").strip().lower()
                if ans in ("y", "yes"):
                    run(["reboot"])
            except EOFError:
                pass


def set_grub_and_session_defaults(dry_run: bool) -> None:
    section("⚙️  GRUB & SESSION DEFAULTS")
    grub_cfg = Path("/boot/grub/grub.cfg")
    if grub_cfg.exists():
        try:
            windows_entry = run(["grep", "-i", "windows", str(grub_cfg)], capture_output=True)
            if windows_entry.stdout:
                match = windows_entry.stdout.split("\n")[0]
                if "'" in match:
                    try:
                        windows_num = match.split("'")[1]
                        if not dry_run:
                            run(["sed", "-i", f's/set default="0"/set default="{windows_num}"/', str(grub_cfg)])
                        print(ok(f"GRUB default set to Windows entry: {windows_num}"))
                    except Exception as e:
                        print(warn(f"Could not extract Windows entry number: {e}"))
                else:
                    print(warn("Windows entry found but no number extracted"))
            else:
                print(warn("No Windows entry found in grub.cfg"))
        except Exception as e:
            print(warn(f"GRUB default update failed: {e}"))
    else:
        print(warn("/boot/grub/grub.cfg not found"))

    xsession_file = Path("/etc/X11/Xsession.d/99-i3-default")
    try:
        if not dry_run:
            xsession_file.parent.mkdir(parents=True, exist_ok=True)
            xsession_file.write_text("exec i3\n")
            xsession_file.chmod(0o644)
        print(ok("i3 set as default in Xsession"))
    except Exception as e:
        print(warn(f"Xsession.d update failed: {e}"))

    try:
        if not dry_run:
            run(["update-alternatives", "--set", "x-session-manager", "/usr/bin/i3"])
        print(ok("i3 set as x-session-manager alternative"))
    except Exception as e:
        print(warn(f"update-alternatives failed: {e}"))

    gdm_conf = Path("/etc/gdm3/custom.conf")
    try:
        if not dry_run:
            if gdm_conf.exists():
                content = gdm_conf.read_text()
                if "[daemon]" not in content or "DefaultSession=i3.desktop" not in content:
                    with gdm_conf.open("a") as f:
                        f.write("\n[daemon]\nDefaultSession=i3.desktop\n")
            else:
                gdm_conf.write_text("[daemon]\nDefaultSession=i3.desktop\n")
        print(ok("GDM3 default session set to i3"))
    except Exception as e:
        print(warn(f"GDM3 custom.conf update failed: {e}"))

# =========================
# Main
# =========================

def main() -> None:
    dry_run = DRY_RUN
    log_path = DEFAULT_LOG

    if os.geteuid() != 0 and not dry_run:
        print(err("Please run as root: sudo python3 startup_best.py"))
        sys.exit(1)
    if os.geteuid() != 0 and dry_run:
        print(warn("Running in dry-run without root; no system changes will be made."))

    header(TARGET_USER)

    startup_dir = detect_or_clone_repo(dry_run)
    if not startup_dir.exists():
        print(warn("startup repo not found; some steps will be skipped"))

    install_packages(log_path, dry_run)
    copy_configs_and_wallpapers(startup_dir, dry_run)
    service_results = install_battery_monitor(startup_dir, log_path, dry_run)
    apply_grub_theme(startup_dir, dry_run)
    make_scripts_executable(dry_run)

    section("🛠 OPTIONAL APPLICATIONS")
    if NO_MENU:
        print(ok("Optional apps menu skipped"))
    else:
        selected = select_menu(OPTIONAL_APPS, no_clear=not CLEAR_SCREEN)
        if any(selected):
            print("\n──────────────────────────────────────────────")
            print("🛠 Installing Optional Applications")
            print("──────────────────────────────────────────────")
            if selected[0]:
                install_telegram(dry_run)
            if selected[1]:
                install_brave(dry_run)
            if selected[2]:
                install_rustscan(dry_run)
        else:
            print(ok("No optional apps selected — skipping"))

    set_i3_default(dry_run)
    set_grub_and_session_defaults(dry_run)
    restart_i3_or_prompt(dry_run)

    # final checklist snippet for battery service
    print("\n" + BOLD + "Final battery-monitor/service checklist:" + RESET)
    results_map = {cmd: (ok_, brief) for (cmd, ok_, brief) in service_results if isinstance(cmd, str)}

    script_path = USER_HOME / ".local" / "bin" / "battery-monitor.sh"
    ok_script = script_path.exists() and (script_path.stat().st_mode & 0o111)
    if ok_script:
        print(f"{ok(CHECK)} Script path exists and executable")
    else:
        print(f"{warn(CROSS)} Script path missing or not executable")

    svc_path = USER_HOME / ".config" / "systemd" / "user" / "battery-monitor.service"
    if svc_path.exists():
        print(f"{ok(CHECK)} Service file copied")
    else:
        print(f"{warn(CROSS)} Service file missing")

    reload_key = "systemctl --user daemon-reload"
    enable_key = "systemctl --user enable --now battery-monitor.service"
    start_key = "systemctl --user start battery-monitor.service"

    if reload_key in results_map and results_map[reload_key][0]:
        print(f"{ok(CHECK)} Service reloaded")
    else:
        print(f"{warn(CROSS)} Service reload not confirmed")

    if enable_key in results_map and results_map[enable_key][0]:
        print(f"{ok(CHECK)} Service enabled & running")
    elif start_key in results_map and results_map[start_key][0]:
        print(f"{ok(CHECK)} Service started")
    else:
        print(f"{warn(CROSS)} Service enable/start not confirmed")

    print("\n" + "═" * 51)
    print(ok("🎉 SETUP COMPLETED"))
    print("═" * 51)
    print("Reboot recommended.")
    print("═" * 51)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n" + warn("Interrupted by user. Exiting cleanly."))
