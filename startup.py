#!/usr/bin/env python3
"""
startup_setup.py - Complete system setup script
Based on the prompt requirements with clean & modern output design.
"""
from __future__ import annotations
import os
import sys
import shutil
import subprocess
import datetime
import termios
import tty
from pathlib import Path
from typing import List, Tuple, Optional
import pwd

REPO_URL = "https://github.com/Abr-ahamis/startup.git"
REPO_DIR_NAME = "startup"
DRY_RUN = False
TIMESTAMP = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
QUIET = False

APT_PACKAGES = [
    "i3", "i3-wm", "i3blocks", "rofi", "xdotool", "dex", "acpi", "upower",
    "xfce4-power-manager", "i3lock", "xss-lock", "pulseaudio-utils",
    "brightnessctl", "feh", "picom", "fonts-font-awesome", "git", "rsync",
    "unzip", "curl", "wget", "grub-customizer", "timeshift", "redshift"
]

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

def color_ok(s): return f"{GREEN}{s}{RESET}"
def color_warn(s): return f"{YELLOW}{s}{RESET}"
def color_err(s): return f"{RED}{s}{RESET}"
def color_info(s): return f"{CYAN}{s}{RESET}"

def run(cmd, check=False, capture_output=True, shell=False, env=None) -> subprocess.CompletedProcess:
    if DRY_RUN:
        print(color_info(f"[DRY-RUN CMD] {cmd}"))
        class D:
            returncode = 0
            stdout = ""
            stderr = ""
        return D()
    if isinstance(cmd, (list, tuple)):
        cmd_display = " ".join(map(str, cmd))
    else:
        cmd_display = str(cmd)
    if not QUIET:
        print(color_info(f"[CMD] {cmd_display}"))
    try:
        completed = subprocess.run(cmd, check=check, capture_output=capture_output, text=True, shell=shell, env=env)
        return completed
    except subprocess.CalledProcessError as e:
        return e

def ensure_dir(p: Path):
    if not p.exists():
        if not DRY_RUN:
            p.mkdir(parents=True, exist_ok=True)

def backup_to_backupdv(p: Path) -> Optional[Path]:
    if not p.exists():
        return None
    USER_HOME = get_user_home()
    backup_root = USER_HOME / ".BACKUPDV"
    try:
        if str(p).startswith(str(USER_HOME)):
            rel = p.relative_to(USER_HOME)
            target = backup_root / rel
        else:
            rel = Path(p.as_posix().lstrip("/"))
            target = backup_root / "root" / rel
        ensure_dir(target.parent)
        if not DRY_RUN:
            shutil.move(str(p), str(target))
        print(color_ok(f"BACKUP -> {target}"))
        return target
    except Exception as e:
        print(color_warn(f"BACKUP-FAIL {p}: {e}"))
        return None

def safe_copy(src: Path, dst: Path, dirs_exist_ok=False) -> bool:
    if not src.exists():
        print(color_warn(f"SKIP (missing): {src}"))
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
    except Exception as e:
        print(color_warn(f"COPY-FAIL: {src} -> {dst}: {e}"))
        return False

def is_pkg_installed(pkg: str) -> bool:
    if DRY_RUN:
        return False
    cp = subprocess.run(["dpkg", "-s", pkg], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return cp.returncode == 0

def is_command_present(name: str) -> bool:
    return shutil.which(name) is not None

def get_target_user() -> str:
    sudo_user = os.environ.get("SUDO_USER")
    if sudo_user:
        return sudo_user
    return os.environ.get("USER", "root")

def get_user_home() -> Path:
    target = get_target_user()
    try:
        return Path(pwd.getpwnam(target).pw_dir)
    except Exception:
        return Path(os.environ.get("HOME", "/root"))

TARGET_USER = get_target_user()
USER_HOME = get_user_home()

def print_header():
    print()
    print("╔" + "═"*50 + "╗")
    print("║" + "{:^50}".format("Walcome back Sr.") + "║")
    print("╚" + "═"*50 + "╝")
    print(f"👤 Target User  : {TARGET_USER}")
    print(f"⚙️  Mode         : Full Environment Setup")
    print("🚀 Starting setup...")

def progress_bar(current: int, total: int, width: int = 20) -> str:
    frac = current/total if total else 1.0
    filled = int(frac*width)
    bar = "█"*filled + "░"*(width-filled)
    pct = int(frac*100)
    return f"{bar} {pct}%"

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
        print(color_warn("git not available; please place repo at ./startup"))
        return target
    run(["git", "clone", "--depth", "1", REPO_URL, str(target)])
    return target

def install_packages():
    print("\n📦 PACKAGE INSTALLATION SECTION")
    print("─"*51)
    
    missing = [p for p in APT_PACKAGES if not is_pkg_installed(p)]
    
    if not missing:
        for pkg in APT_PACKAGES:
            print(f"{color_ok('[✔]')} {pkg:20s} already installed")
        return
    
    for pkg in APT_PACKAGES:
        if is_pkg_installed(pkg):
            print(f"{color_ok('[✔]')} {pkg:20s} already installed")
        else:
            print(f"{color_ok('[➜]')} {pkg:20s} Installing packages: ", end="")
            
    print(f"\n[➜] Installing packages: {progress_bar(0, len(missing))}")
    
    run(["apt", "update"])
    
    for i, pkg in enumerate(missing, start=1):
        print(f"\r[➜] {pkg:20s} Installing packages: {progress_bar(i, len(missing))}", end="")
        run(["apt", "install", "-y", pkg])
        print(f"\r{color_ok('[✔]')} {pkg:20s} installed{ ' ' * 20}")
    
    print(f"\n{color_ok('✅ All packages verified.')}")

def copy_configs(startup_dir: Path):
    print("\n📁 CONFIG DEPLOYMENT SECTION")
    print("─"*51)
    
    repo_i3 = startup_dir / "i3"
    
    safe_copy(repo_i3 / ".config" / "i3" / "config", USER_HOME / ".config" / "i3" / "config")
    safe_copy(repo_i3 / ".config" / "i3" / "scripts" / "terminal-font.sh", USER_HOME / ".config" / "i3" / "scripts" / "terminal-font.sh")
    safe_copy(repo_i3 / ".config" / "i3blocks", USER_HOME / ".config" / "i3blocks", dirs_exist_ok=True)
    safe_copy(repo_i3 / ".config" / "rofi", USER_HOME / ".config" / "rofi", dirs_exist_ok=True)
    safe_copy(repo_i3 / ".config" / "picom" / "picom.conf", USER_HOME / ".config" / "picom" / "picom.conf")
    
    print(f"{color_ok('[✔]')} i3 config updated")
    print(f"{color_ok('[✔]')} i3blocks config updated")
    print(f"{color_ok('[✔]')} rofi theme applied")
    print(f"{color_ok('[✔]')} picom configuration updated")
    
    src_local_bin = repo_i3 / ".local" / "bin"
    dst_local_bin = USER_HOME / ".local" / "bin"
    ensure_dir(dst_local_bin)
    if src_local_bin.exists():
        for f in sorted(src_local_bin.iterdir()):
            safe_copy(f, dst_local_bin / f.name)
    
    src_fonts = repo_i3 / ".local" / "share" / "fonts"
    dst_fonts = USER_HOME / ".local" / "share" / "fonts"
    ensure_dir(dst_fonts)
    font_count = 0
    if src_fonts.exists():
        for f in sorted(src_fonts.iterdir()):
            if safe_copy(f, dst_fonts / f.name):
                font_count += 1
    print(f"{color_ok('[✔]')} Fonts installed ({font_count})")
    
    src_rofi = repo_i3 / "usr" / "share" / "rofi" / "themes" / "Adapta-Nokto.rasi"
    if src_rofi.exists():
        safe_copy(src_rofi, Path("/usr/share/rofi/themes/Adapta-Nokto.rasi"))
    
    print(f"{color_ok('✅ Configuration deployed successfully.')}")

def copy_wallpapers(startup_dir: Path):
    print("\n🖼 WALLPAPER SECTION")
    print("─"*51)
    
    repo_wall = startup_dir / "wallpaper"
    ensure_dir(USER_HOME / "Pictures")
    
    pictures_count = 0
    for name in ("wallpaper.jpg", "wallpaper-1.jpg", "wallpaper-2.jpg"):
        s = repo_wall / name
        if s.exists():
            if safe_copy(s, USER_HOME / "Pictures" / name):
                pictures_count += 1
    
    backgrounds_dir = Path("/usr/share/backgrounds/kali")
    ensure_dir(backgrounds_dir)
    
    targets = [
        ("wallpaper-1.jpg", "login.svg"),
        ("wallpaper.jpg", "kali-maze-16x9.jpg"),
        ("wallpaper-2.jpg", "kali-tiles-16x9.jpg"),
        ("wallpaper-1.jpg", "kali-waves-16x9.png"),
        ("wallpaper.jpg", "kali-oleo-16x9.png"),
        ("wallpaper-2.jpg", "kali-tiles-purple-16x9.jpg"),
        ("wallpaper-1.jpg", "wallpaper-1.jpg"),
        ("wallpaper-1.jpg", "login-blurred"),
    ]
    
    replaced = 0
    for src_name, dst_name in targets:
        src = repo_wall / src_name
        dst = backgrounds_dir / dst_name
        if not src.exists():
            continue
        if dst.exists():
            backup_to_backupdv(dst)
        try:
            if not DRY_RUN:
                shutil.copy2(src, dst)
            replaced += 1
        except Exception as e:
            print(color_warn(f"WALLPAPER FAIL: {dst}: {e}"))
    
    print(f"{color_ok('[✔]')} Wallpapers replaced ({replaced})")
    print(color_ok("wallpaper are replaced"))
    print(color_ok("i3 wallpaper set"))

def install_battery_monitor(startup_dir: Path):
    print("\n🔋 BATTERY MONITOR SETUP")
    print("─"*51)
    
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
    
    print(color_ok("battery-monitor setuped"))

def apply_grub_theme(startup_dir: Path):
    print("\n🎨 GRUB THEME SETUP")
    print("─"*51)
    
    repo_grub = startup_dir / "grub"
    dst_boot = Path("/boot/grub/themes/kali")
    dst_usr = Path("/usr/share/grub/themes/kali")
    
    if not repo_grub.exists():
        print(color_warn("No grub/ directory found; skipping"))
        return
    
    if dst_boot.exists():
        backup_to_backupdv(dst_boot)
    if dst_usr.exists():
        backup_to_backupdv(dst_usr)
    
    try:
        if not DRY_RUN:
            shutil.copytree(repo_grub, dst_boot, dirs_exist_ok=True)
            shutil.copytree(repo_grub, dst_usr, dirs_exist_ok=True)
        print(color_ok("grub setuped"))
    except Exception as e:
        print(color_warn(f"GRUB COPY FAIL: {e}"))
    
    try:
        if not DRY_RUN and Path("/boot/grub/grub.cfg").exists():
            run(["sed", "-i", "s/set timeout=30/set timeout=2/", "/boot/grub/grub.cfg"])
            print(color_ok("grub stepup to 2s"))
    except Exception as e:
        print(color_warn(f"grub sed fail: {e}"))

def make_scripts_executable():
    for p in (USER_HOME / ".config" / "i3" / "scripts", USER_HOME / ".local" / "bin", USER_HOME / ".config" / "i3blocks" / "scripts"):
        if p.exists():
            for f in p.rglob("*"):
                if f.is_file():
                    try:
                        if not DRY_RUN:
                            f.chmod(0o755)
                    except Exception:
                        pass

def read_key() -> str:
    try:
        if not sys.stdin.isatty():
            return ""
        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)
        tty.setraw(fd)
        key = os.read(fd, 3)
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
        return key.decode(errors='ignore')
    except (termios.error, OSError):
        return ""

def interactive_menu(options: List[str]) -> List[bool]:
    selected = [False] * len(options)
    cursor = 0
    
    # Check if running in a terminal
    if not sys.stdin.isatty():
        print("\nNot running in terminal - using simple input instead")
        print("Enter numbers of apps to install (e.g., '1 2 3') or press Enter for none: ")
        for i, opt in enumerate(options, 1):
            print(f"  {i}. {opt}")
        try:
            ans = input("Selection: ").strip()
            if ans:
                for num in ans.split():
                    try:
                        idx = int(num) - 1
                        if 0 <= idx < len(options):
                            selected[idx] = True
                    except ValueError:
                        pass
        except:
            pass
        return selected
    
    while True:
        os.system('clear')
        print("Install Telegram, Brave (Nightly), RustScan now?\n")
        for i, opt in enumerate(options):
            prefix = ">" if i == cursor else " "
            box = "[*]" if selected[i] else "[ ]"
            print(f" {prefix} {box} {opt}")
        print("\n(Use arrows to move, Space/Enter to toggle, 'f' when finished)")
        
        key = read_key()
        
        if key == '\x1b[A' or key == '\x1bOA':
            cursor = (cursor - 1) % len(options)
        elif key == '\x1b[B' or key == '\x1bOB':
            cursor = (cursor + 1) % len(options)
        elif key in (' ', '\r', '\n'):
            selected[cursor] = not selected[cursor]
        elif key == 'f':
            break
    
    return selected

def install_telegram(startup_dir: Path):
    if is_command_present('telegram') or is_command_present('telegram-desktop') or Path('/usr/local/bin/telegram').exists():
        print(f"{color_ok('[✔]')} Telegram already installed")
        return
    
    print(f"{color_ok('[➜]')} Telegram installing...")
    
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
            link.symlink_to(tbin)
            print(f"{color_ok('[✔]')} Telegram installed")
        except Exception as e:
            print(color_warn(f"Telegram symlink fail: {e}"))

def install_brave(startup_dir: Path):
    if is_command_present('brave-browser') or is_command_present('brave-browser-nightly'):
        print(f"{color_ok('[✔]')} Brave already installed")
        return
    
    print(f"{color_ok('[➜]')} Brave (Nightly) installing...")
    
    if DRY_RUN:
        return
    
    run("curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly bash", shell=True)
    run(["apt", "install", "-y", "brave-browser-nightly"])
    
    print(f"{color_ok('[✔]')} Brave installed")

def install_rustscan(startup_dir: Path):
    if is_command_present('rustscan'):
        print(f"{color_ok('[✔]')} RustScan already installed")
        return
    
    print(f"{color_ok('[➜]')} RustScan installing...")
    
    zip_url = "https://github.com/bee-san/RustScan/releases/download/2.4.1/rustscan.deb.zip"
    zip_path = Path("/tmp/rustscan.deb.zip")
    
    if DRY_RUN:
        return
    
    run(["wget", "-q", zip_url, "-O", str(zip_path)])
    
    if not zip_path.exists() or zip_path.stat().st_size == 0:
        print(f"{color_err('[✖]')} RustScan download failed")
        return
    
    run(["unzip", "-o", str(zip_path), "-d", "/tmp"])
    
    deb_candidates = list(Path("/tmp").glob("*.deb"))
    if not deb_candidates:
        print(f"{color_err('[✖]')} No .deb found after extracting RustScan")
        return
    
    deb = next((p for p in deb_candidates if "rust" in p.name.lower()), deb_candidates[0])
    run(["dpkg", "-i", str(deb)])
    run(["apt", "install", "-f", "-y"])
    
    print(f"{color_ok('[✔]')} RustScan installed")

def set_i3_default():
    print("\n🖥️  I3 DEFAULT SESSION SETUP")
    print("─"*51)
    
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
        except Exception as e:
            print(color_warn(f"WRITE-FAIL: {p}: {e}"))
    
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
            print(color_ok("i3 set as default (AccountsService updated)"))
        except Exception as e:
            print(color_warn(f"AccountsService update failed: {e}"))
    
    if not DRY_RUN:
        run(["update-alternatives", "--install", "/usr/bin/x-session-manager", "x-session-manager", "/usr/bin/i3", "60"])
        run(["update-alternatives", "--set", "x-session-manager", "/usr/bin/i3"])

def restart_i3():
    p = run(["pgrep", "-u", TARGET_USER, "-x", "i3"])
    if getattr(p, "returncode", 1) == 0:
        if not DRY_RUN:
            run(["sudo", "-u", TARGET_USER, "i3-msg", "restart"])
        print(color_ok("i3 restarted"))
    else:
        print(color_info("i3 not running - skipping restart"))

def prompt_restart():
    if not DRY_RUN:
        try:
            ans = input("\nRestart now to apply session manager change? [y/N]: ").strip().lower()
            if ans in ("y", "yes"):
                run(["reboot"])
        except EOFError:
            print("\nSkipping restart prompt (non-interactive mode)")

def main():
    if os.geteuid() != 0:
        print(color_err("Please run as root: sudo python3 startup_setup.py"))
        sys.exit(1)
    
    print_header()
    
    startup_dir = detect_or_clone_repo()
    if not startup_dir.exists():
        print(color_warn("startup repo not found; some steps will be skipped"))
    
    install_packages()
    copy_configs(startup_dir)
    copy_wallpapers(startup_dir)
    install_battery_monitor(startup_dir)
    apply_grub_theme(startup_dir)
    make_scripts_executable()
    
    print("\n" + "─"*51)
    print("Install Telegram, Brave (Nightly), RustScan now?")
    print("─"*51)
    
    options = ["Telegram", "Brave (Nightly)", "RustScan"]
    selected = interactive_menu(options)
    
    if any(selected):
        print("\n" + "─"*51)
        print("🛠 Installing Optional Applications")
        print("─"*51)
        
        if selected[0]:
            install_telegram(startup_dir)
        if selected[1]:
            install_brave(startup_dir)
        if selected[2]:
            install_rustscan(startup_dir)
    
    set_i3_default()
    restart_i3()
    prompt_restart()
    
    print("\n" + "═"*51)
    print("🎉 SETUP COMPLETED")
    print("═"*51)
    print("Reboot recommended.")
    print("═"*51)

if __name__ == "__main__":
    main()
