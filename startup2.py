#!/usr/bin/env python3
"""
gpt.py - Clean, modern setup script based on prompt instructions.

Highlights:
- Backups replaced files into ~/.BACKUPDV (no timestamps)
- Clean output (no file spam), with sections and compact statuses
- Installs only missing apt packages with progress bar
- Interactive optional-apps menu (arrows + space/enter, 'f' to finish)
- Applies wallpapers, grub theme, battery monitor, i3 default session
"""
from __future__ import annotations

import os
import sys
import shutil
import subprocess
import termios
import tty
from pathlib import Path
from typing import List, Tuple, Optional
import pwd

# =========================
# Configuration
# =========================
REPO_URL = "https://github.com/Abr-ahamis/startup.git"
REPO_DIR_NAME = "startup"
DRY_RUN = False
BACKUP_ROOT_NAME = ".BACKUPDV"

APT_PACKAGES = [
    "i3", "i3-wm", "i3blocks", "rofi", "xdotool", "dex", "acpi", "upower",
    "xfce4-power-manager", "i3lock", "xss-lock", "pulseaudio-utils",
    "brightnessctl", "feh", "picom", "fonts-font-awesome", "git", "rsync",
    "unzip", "curl", "wget", "grub-customizer", "timeshift", "redshift"
]

OPTIONAL_APPS = ["Telegram", "Brave (Nightly)", "RustScan"]

# =========================
# UI helpers
# =========================
CSI = "\033["
RESET = CSI + "0m"
GREEN = CSI + "32m"
YELLOW = CSI + "33m"
RED = CSI + "31m"
CYAN = CSI + "36m"

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
    print("╔" + "═"*46 + "╗")
    print("║" + "{:^46}".format("Walcome back Sr.") + "║")
    print("╚" + "═"*46 + "╝")
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

# =========================
# Utilities
# =========================
def run(cmd, check: bool = False, capture_output: bool = True, shell: bool = False) -> subprocess.CompletedProcess:
    if DRY_RUN:
        return subprocess.CompletedProcess(cmd, 0, "", "")
    return subprocess.run(cmd, check=check, capture_output=capture_output, text=True, shell=shell)

def ensure_dir(p: Path) -> None:
    if not p.exists():
        if not DRY_RUN:
            p.mkdir(parents=True, exist_ok=True)

def backup_to_backupdv(dst: Path) -> Optional[Path]:
    if not dst.exists():
        return None
    ensure_dir(BACKUP_ROOT)
    try:
        if str(dst).startswith(str(USER_HOME)):
            rel = dst.relative_to(USER_HOME)
            target = BACKUP_ROOT / rel
        else:
            rel = Path(dst.as_posix().lstrip("/"))
            target = BACKUP_ROOT / "root" / rel
        ensure_dir(target.parent)
        if not DRY_RUN:
            shutil.move(str(dst), str(target))
        return target
    except Exception:
        return None

def safe_copy(src: Path, dst: Path, dirs_exist_ok: bool = False) -> bool:
    if not src.exists():
        return False
    ensure_dir(dst.parent)
    if dst.exists():
        backup_to_backupdv(dst)
    try:
        if src.is_dir():
            if not DRY_RUN:
                shutil.copytree(src, dst, dirs_exist_ok=dirs_exist_ok)
        else:
            if not DRY_RUN:
                shutil.copy2(src, dst)
        return True
    except Exception:
        return False

def is_pkg_installed(pkg: str) -> bool:
    if DRY_RUN:
        return False
    cp = subprocess.run(["dpkg", "-s", pkg], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return cp.returncode == 0

def is_command_present(name: str) -> bool:
    return shutil.which(name) is not None

# =========================
# Repo
# =========================
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
        return target
    run(["git", "clone", "--depth", "1", REPO_URL, str(target)])
    return target

# =========================
# Core steps
# =========================
def install_packages() -> None:
    section("📦 PACKAGE INSTALLATION SECTION")
    missing = [p for p in APT_PACKAGES if not is_pkg_installed(p)]

    if not missing:
        for pkg in APT_PACKAGES:
            print(ok(f"[✔] {pkg:<18} already installed"))
        return

    # show already installed
    for pkg in APT_PACKAGES:
        if is_pkg_installed(pkg):
            print(ok(f"[✔] {pkg:<18} already installed"))

    if not DRY_RUN:
        run(["apt", "update"])

    total = len(missing)
    for i, pkg in enumerate(missing, start=1):
        bar = progress_bar(i - 1, total)
        print(f"[➜] {pkg:<18} Installing packages: {bar}", end="\r", flush=True)
        try:
            if not DRY_RUN:
                subprocess.run(
                    ["apt", "install", "-y", "-qq", pkg],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.STDOUT,
                    check=True,
                )
            bar = progress_bar(i, total)
            print(" " * 120, end="\r")
            print(ok(f"[✔] {pkg:<18} installed {bar}"))
        except Exception:
            print(" " * 120, end="\r")
            print(warn(f"[✖] {pkg:<18} failed"))

    print(ok("✅ All packages verified."))

def copy_configs_and_wallpapers(startup_dir: Path) -> None:
    section("📁 CONFIG DEPLOYMENT SECTION")

    repo_i3 = startup_dir / "i3"
    success = {
        "i3": safe_copy(repo_i3 / ".config" / "i3" / "config", USER_HOME / ".config" / "i3" / "config"),
        "i3blocks": safe_copy(repo_i3 / ".config" / "i3blocks", USER_HOME / ".config" / "i3blocks", dirs_exist_ok=True),
        "rofi": safe_copy(repo_i3 / ".config" / "rofi", USER_HOME / ".config" / "rofi", dirs_exist_ok=True),
        "picom": safe_copy(repo_i3 / ".config" / "picom" / "picom.conf", USER_HOME / ".config" / "picom" / "picom.conf"),
    }

    # i3 scripts
    safe_copy(
        repo_i3 / ".config" / "i3" / "scripts" / "terminal-font.sh",
        USER_HOME / ".config" / "i3" / "scripts" / "terminal-font.sh",
    )

    # local bin scripts
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
    font_count = 0
    if src_fonts.exists():
        for f in sorted(src_fonts.iterdir()):
            if safe_copy(f, dst_fonts / f.name):
                font_count += 1

    # rofi system theme
    src_rofi = repo_i3 / "usr" / "share" / "rofi" / "themes" / "Adapta-Nokto.rasi"
    if src_rofi.exists():
        safe_copy(src_rofi, Path("/usr/share/rofi/themes/Adapta-Nokto.rasi"))

    print(ok("[✔] i3 config updated") if success["i3"] else warn("[✖] i3 config update failed"))
    print(ok("[✔] i3blocks config updated") if success["i3blocks"] else warn("[✖] i3blocks update failed"))
    print(ok("[✔] rofi theme applied") if success["rofi"] else warn("[✖] rofi update failed"))
    print(ok("[✔] picom configuration updated") if success["picom"] else warn("[✖] picom update failed"))
    print(ok(f"[✔] Fonts installed ({font_count})"))

    # Wallpapers
    section("🖼 WALLPAPER SECTION")
    repo_wall = startup_dir / "wallpaper"
    ensure_dir(USER_HOME / "Pictures")
    for name in ("wallpaper.jpg", "wallpaper-1.jpg", "wallpaper-2.jpg"):
        s = repo_wall / name
        if s.exists():
            safe_copy(s, USER_HOME / "Pictures" / name)

    backgrounds_dir = Path("/usr/share/backgrounds/kali")
    ensure_dir(backgrounds_dir)

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
            backup_to_backupdv(dst)
        try:
            if not DRY_RUN:
                shutil.copy2(src, dst)
            replaced += 1
        except Exception:
            pass

    print(ok(f"[✔] Wallpapers replaced ({replaced})"))
    print(ok("wallpaper are replaced"))

    # Ensure wallpaper-1.jpg exists for i3 (skip if already there)
    i3_wallpaper = backgrounds_dir / "wallpaper-1.jpg"
    src_i3 = repo_wall / "wallpaper-1.jpg"
    if src_i3.exists():
        if not i3_wallpaper.exists():
            safe_copy(src_i3, i3_wallpaper)
        print(ok("i3 wallpaper set"))

def install_battery_monitor(startup_dir: Path) -> None:
    section("🔋 BATTERY MONITOR SETUP")
    repo_script = startup_dir / "i3" / ".local" / "bin" / "battery-monitor.sh"
    repo_service = startup_dir / "i3" / ".config" / "systemd" / "user" / "battery-monitor.service"
    dst_script = USER_HOME / ".local" / "bin" / "battery-monitor.sh"
    dst_service = USER_HOME / ".config" / "systemd" / "user" / "battery-monitor.service"

    if repo_script.exists():
        safe_copy(repo_script, dst_script)
        try:
            if not DRY_RUN:
                dst_script.chmod(0o755)
        except Exception:
            pass
    if repo_service.exists():
        safe_copy(repo_service, dst_service)

    # systemctl --user as target user
    try:
        uid = pwd.getpwnam(TARGET_USER).pw_uid
        runtime_dir = f"/run/user/{uid}"
        cmd = f"XDG_RUNTIME_DIR={runtime_dir} systemctl --user daemon-reload"
        run(["sudo", "-u", TARGET_USER, "bash", "-lc", cmd])
        cmd = f"XDG_RUNTIME_DIR={runtime_dir} systemctl --user enable --now battery-monitor.service"
        run(["sudo", "-u", TARGET_USER, "bash", "-lc", cmd])
    except Exception:
        pass

    print(ok("battery-monitor setuped"))

def apply_grub_theme(startup_dir: Path) -> None:
    section("🎨 GRUB THEME SETUP")
    repo_grub = startup_dir / "grub"
    dst_boot = Path("/boot/grub/themes/kali")
    dst_usr = Path("/usr/share/grub/themes/kali")
    if not repo_grub.exists():
        print(warn("No grub/ directory found; skipping"))
        return
    if dst_boot.exists():
        backup_to_backupdv(dst_boot)
    if dst_usr.exists():
        backup_to_backupdv(dst_usr)
    try:
        if not DRY_RUN:
            shutil.copytree(repo_grub, dst_boot, dirs_exist_ok=True)
            shutil.copytree(repo_grub, dst_usr, dirs_exist_ok=True)
        print(ok("grub setuped"))
    except Exception:
        print(warn("grub copy failed"))
    try:
        if not DRY_RUN and Path("/boot/grub/grub.cfg").exists():
            subprocess.run(["sed", "-i", "s/set timeout=30/set timeout=2/", "/boot/grub/grub.cfg"], check=False)
            print(ok("grub stepup to 2s"))
    except Exception:
        print(warn("grub timeout update failed"))

def make_scripts_executable() -> None:
    for p in (
        USER_HOME / ".config" / "i3" / "scripts",
        USER_HOME / ".local" / "bin",
        USER_HOME / ".config" / "i3blocks" / "scripts",
    ):
        if p.exists():
            for f in p.rglob("*"):
                if f.is_file():
                    try:
                        if not DRY_RUN:
                            f.chmod(0o755)
                    except Exception:
                        pass

# =========================
# Optional apps menu
# =========================
def read_key() -> str:
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        ch = os.read(fd, 3)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
    return ch.decode(errors="ignore")

def select_menu(options: List[str]) -> List[bool]:
    selected = [False] * len(options)
    cursor = 0
    running = True

    if not sys.stdin.isatty():
        return selected

    while running:
        os.system("clear")
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
            running = False
    return selected

def install_telegram() -> None:
    if is_command_present("telegram") or is_command_present("telegram-desktop") or Path("/usr/local/bin/telegram").exists():
        print(ok("[✔] Telegram already installed"))
        return
    print(ok("[➜] Telegram installing..."))
    tfile = Path("/tmp/tsetup.tar.xz")
    if DRY_RUN:
        return
    run(["wget", "-q", "https://telegram.org/dl/desktop/linux", "-O", str(tfile)])
    opt = Path("/opt/Telegram")
    if opt.exists():
        backup_to_backupdv(opt)
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
            backup_to_backupdv(link)
        try:
            if not DRY_RUN:
                link.symlink_to(tbin)
            print(ok("[✔] Telegram installed"))
        except Exception:
            print(warn("[✖] Telegram installation failed"))

def install_brave() -> None:
    if is_command_present("brave-browser") or is_command_present("brave-browser-nightly"):
        print(ok("[✔] Brave already installed"))
        return
    print(ok("[➜] Brave (Nightly) installing..."))
    if DRY_RUN:
        return
    run("curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly sh", shell=True)
    run(["apt", "install", "-y", "brave-browser-nightly"])
    print(ok("[✔] Brave installed"))

def install_rustscan() -> None:
    if is_command_present("rustscan"):
        print(ok("[✔] RustScan already installed"))
        return
    print(ok("[➜] RustScan installing..."))
    zip_url = "https://github.com/bee-san/RustScan/releases/download/2.4.1/rustscan.deb.zip"
    zip_path = Path("/tmp/rustscan.deb.zip")
    if DRY_RUN:
        return
    run(["wget", "-q", zip_url, "-O", str(zip_path)])
    if not zip_path.exists() or zip_path.stat().st_size == 0:
        print(warn("[✖] RustScan download failed"))
        return
    run(["unzip", "-o", str(zip_path), "-d", "/tmp"])
    deb_candidates = list(Path("/tmp").glob("*.deb"))
    if not deb_candidates:
        print(warn("[✖] No .deb found after extracting RustScan"))
        return
    deb = next((p for p in deb_candidates if "rust" in p.name.lower()), deb_candidates[0])
    run(["dpkg", "-i", str(deb)])
    run(["apt", "install", "-f", "-y"])
    print(ok("[✔] RustScan installed"))

# =========================
# i3 default and restart
# =========================
def set_i3_default() -> None:
    xinit = USER_HOME / ".xinitrc"
    xsession = USER_HOME / ".xsession"
    content = "exec i3\n"
    for p in (xinit, xsession):
        if p.exists():
            backup_to_backupdv(p)
        try:
            if not DRY_RUN:
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
            backup_to_backupdv(acct)
            if not DRY_RUN:
                acct.write_text(txt)
        except Exception:
            pass

    run(["update-alternatives", "--install", "/usr/bin/x-session-manager", "x-session-manager", "/usr/bin/i3", "60"])
    run(["update-alternatives", "--set", "x-session-manager", "/usr/bin/i3"])

def restart_i3_or_prompt() -> None:
    p = run(["pgrep", "-u", TARGET_USER, "-x", "i3"])
    if getattr(p, "returncode", 1) == 0:
        if not DRY_RUN:
            run(["sudo", "-u", TARGET_USER, "i3-msg", "restart"])
    else:
        try:
            ans = input("Restart now to apply session manager change? [y/N]: ").strip().lower()
            if ans in ("y", "yes"):
                run(["reboot"])
        except EOFError:
            pass

# =========================
# Main
# =========================
def main() -> None:
    if os.geteuid() != 0:
        print(err("Please run as root: sudo python3 gpt.py"))
        sys.exit(1)

    header(TARGET_USER)

    startup_dir = detect_or_clone_repo()
    if not startup_dir.exists():
        print(warn("startup repo not found; some steps will be skipped"))

    install_packages()
    copy_configs_and_wallpapers(startup_dir)
    install_battery_monitor(startup_dir)
    apply_grub_theme(startup_dir)
    make_scripts_executable()

    section("🛠 OPTIONAL APPLICATIONS")
    selected = select_menu(OPTIONAL_APPS)
    if any(selected):
        print("\n──────────────────────────────────────────────")
        print("🛠 Installing Optional Applications")
        print("──────────────────────────────────────────────")
        if selected[0]:
            install_telegram()
        if selected[1]:
            install_brave()
        if selected[2]:
            install_rustscan()
    else:
        print(ok("No optional apps selected — skipping"))

    set_i3_default()
    restart_i3_or_prompt()

    print("\n══════════════════════════════════════════════")
    print(ok("🎉 SETUP COMPLETED"))
    print("══════════════════════════════════════════════")
    print("Reboot recommended.")
    print("══════════════════════════════════════════════")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n" + warn("Interrupted by user. Exiting cleanly."))
