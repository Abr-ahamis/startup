#!/usr/bin/env python3
"""
startup_setup_full.py

Purpose:
  - Clone/detect a "startup" repo.
  - Install required apt packages first.
  - Backup existing config files carefully.
  - Copy configurations (i3, rofi, etc.) to the user's home.
  - Setup Battery Monitor (systemd --user).
  - Install Apps interactively (Telegram, Brave, VSCode, Spotify, etc.).
  - Apply tweaks (GRUB, Terminal).

Usage:
  sudo python3 startup_setup_full.py
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
import time

# ----------------------
# CONFIGURATION
# ----------------------
REPO_URL = "https://github.com/Abr-ahamis/startup.git"
REPO_DIR_NAME = "startup"

# [EXPLAINER]
# This list controls which system packages are installed via 'apt-get install'
# at the very beginning. If you need a tool like 'htop' or 'zsh', add it here.
APT_PACKAGES = [
    "i3-wm", "i3blocks", "rofi", "xdotool", "dex", "acpi", "upower",
    "xfce4-power-manager", "i3lock", "xss-lock", "pulseaudio-utils",
    "brightnessctl", "feh", "picom", "fonts-font-awesome", "git", "rsync",
    "unzip", "curl", "wget", "grub-customizer", "timeshift", "gpg"
]

# [EXPLAINER]
# This dictionary maps a number to an App Name.
# To add a NEW app:
# 1. Add a line here (e.g., 8: "obsidian").
# 2. Scroll down to 'prompt_multi_select' and update the print list.
# 3. Create a 'def install_obsidian():' function.
# 4. Update 'main()' to call that function if selected.
APP_OPTIONS = {
    1: "telegram",
    2: "brave-nightly",
    3: "vscode",
    4: "protonvpn",
    5: "virtualbox",
    6: "rustscan",
    7: "spotify",
}

# ----------------------
# LOGGING SETUP
# ----------------------
logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
log = logging.getLogger("startup_setup")


# ----------------------
# USER DETECTION
# ----------------------
def get_target_user() -> str:
    """Detect the actual user (not root) if run with sudo."""
    sudo_user = os.environ.get("SUDO_USER")
    if sudo_user:
        return sudo_user
    return os.environ.get("USER", "root")

def get_user_home(user: str) -> Path:
    return Path(pwd.getpwnam(user).pw_dir)

TARGET_USER = get_target_user()
USER_HOME = get_user_home(TARGET_USER)
log.info(f"Target user: {TARGET_USER}, home: {USER_HOME}")


# ----------------------
# UTILITIES (Helper Functions)
# ----------------------
def die(msg: str, code: int = 1):
    log.error(msg)
    sys.exit(code)

def run(cmd, check: bool = False, capture_output: bool = False, env: Optional[dict] = None, shell: bool = False):
    """
    Executes a shell command.
    usage: run(["ls", "-la"]) or run("ls -la", shell=True)
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
                try: dst.unlink()
                except: pass
    try:
        if src.is_dir():
            log.info(f"[COPY-DIR] {src} -> {dst}")
            shutil.copytree(src, dst, dirs_exist_ok=dirs_exist_ok)
        else:
            log.info(f"[COPY-FILE] {src} -> {dst}")
            shutil.copy2(src, dst)
        try:
            chown_recursive(dst, TARGET_USER)
        except:
            pass
        return True
    except Exception as e:
        log.warning(f"[WARN] Copy failed {src} -> {dst}: {e}")
        return False

def require_root():
    if os.geteuid() != 0:
        die("This script must be run as root. Use sudo python3 startup_setup_full.py")


# ----------------------
# CORE LOGIC
# ----------------------

def detect_or_clone_repo() -> Path:
    cwd = Path.cwd()
    if (cwd / "i3").is_dir() and (cwd / "grub").is_dir():
        log.info("[INFO] Using current directory as startup repo.")
        return cwd
    if (cwd / REPO_DIR_NAME).is_dir():
        return cwd / REPO_DIR_NAME
    target = cwd / REPO_DIR_NAME
    log.info(f"[INFO] Cloning {REPO_URL} -> {target}")
    run(["git", "clone", REPO_URL, str(target)], check=False)
    return target

def install_apt_packages(packages: List[str]):
    if not packages: return
    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    log.info("[APT] Updating and installing packages...")
    run(["apt", "update"], check=False, env=env)
    run(["apt", "install", "-y"] + packages, check=False, env=env)

def copy_core_configs(startup_dir: Path):
    log.info("[COPY] Copying configs...")
    repo_i3 = startup_dir / "i3"
    
    # 1. i3 Config
    safe_copy(repo_i3 / ".config" / "i3" / "config", USER_HOME / ".config" / "i3" / "config")
    
    # 2. i3 Scripts (Copy folder content)
    src_scripts = repo_i3 / ".config" / "i3" / "scripts"
    dst_scripts = USER_HOME / ".config" / "i3" / "scripts"
    if src_scripts.exists():
        ensure_dir(dst_scripts)
        for f in src_scripts.iterdir():
            if f.is_file():
                safe_copy(f, dst_scripts / f.name)

    # 3. Directories (i3blocks, rofi)
    safe_copy(repo_i3 / ".config" / "i3blocks", USER_HOME / ".config" / "i3blocks", dirs_exist_ok=True)
    safe_copy(repo_i3 / ".config" / "rofi", USER_HOME / ".config" / "rofi", dirs_exist_ok=True)

    # 4. Picom
    safe_copy(repo_i3 / ".config" / "picom" / "picom.conf", USER_HOME / ".config" / "picom" / "picom.conf")

    # 5. Local Bin
    src_bin = repo_i3 / ".local" / "bin"
    dst_bin = USER_HOME / ".local" / "bin"
    ensure_dir(dst_bin)
    if src_bin.exists():
        for f in src_bin.iterdir():
            safe_copy(f, dst_bin / f.name)

    # 6. Fonts
    src_fonts = repo_i3 / ".local" / "share" / "fonts"
    dst_fonts = USER_HOME / ".local" / "share" / "fonts"
    ensure_dir(dst_fonts)
    if src_fonts.exists():
        for f in src_fonts.iterdir():
            safe_copy(f, dst_fonts / f.name)

    # 7. Update .bashrc PATH
    bashrc = USER_HOME / ".bashrc"
    path_line = 'export PATH="$HOME/.local/bin:$PATH"'
    if bashrc.exists():
        if path_line not in bashrc.read_text():
            with open(bashrc, "a") as f: f.write(f"\n{path_line}\n")
    else:
        with open(bashrc, "w") as f: f.write(f"{path_line}\n")
    
    # 8. Wallpapers
    repo_wall = startup_dir / "wallpaper"
    ensure_dir(USER_HOME / "Pictures")
    for name in ["wallpaper.jpg", "wallpaper-1.jpg", "wallpaper-2.jpg"]:
        s = repo_wall / name
        if s.exists():
            safe_copy(s, USER_HOME / "Pictures" / name)
            # Try copy to system background for login screen usage
            try:
                bg_dir = Path("/usr/share/backgrounds/kali")
                ensure_dir(bg_dir)
                shutil.copy2(s, bg_dir / name)
            except: pass


# ----------------------
# BATTERY MONITOR (Updated)
# ----------------------
def install_battery_monitor(startup_dir: Path):
    """
    Installs script/service and runs the specific sequence:
    systemctl --user daemon-reexec && systemctl --user daemon-reload && systemctl --user restart battery-monitor.service
    """
    repo_script = startup_dir / "i3" / ".local" / "bin" / "battery-monitor.sh"
    repo_service = startup_dir / "i3" / ".config" / "systemd" / "user" / "battery-monitor.service"
    
    dst_script = USER_HOME / ".local" / "bin" / "battery-monitor.sh"
    dst_service = USER_HOME / ".config" / "systemd" / "user" / "battery-monitor.service"

    # Copy files
    if repo_script.exists():
        safe_copy(repo_script, dst_script)
        run(["chmod", "+x", str(dst_script)])
    
    if repo_service.exists():
        safe_copy(repo_service, dst_service)
        # Ensure DBUS var in service file
        try:
            txt = dst_service.read_text()
            if "DBUS_SESSION_BUS_ADDRESS" not in txt:
                log.info("[BATTERY] Injecting DBUS env into service file...")
                lines = txt.splitlines()
                # Insert after [Service]
                new_lines = []
                for line in lines:
                    new_lines.append(line)
                    if line.strip() == "[Service]":
                        new_lines.append("Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%U/bus")
                dst_service.write_text("\n".join(new_lines) + "\n")
                chown_recursive(dst_service, TARGET_USER)
        except Exception as e:
            log.warning(f"[WARN] Failed to edit service file: {e}")

    # RUN THE REQUESTED COMMAND SEQUENCE
    # We must run this as the Target User, not Root.
    # We must set XDG_RUNTIME_DIR so systemctl --user knows where to look.
    try:
        uid = pwd.getpwnam(TARGET_USER).pw_uid
        
        # The exact command chain you requested:
        # 1. daemon-reexec
        # 2. daemon-reload
        # 3. restart service
        cmds = (
            f"export XDG_RUNTIME_DIR=/run/user/{uid}; "
            "systemctl --user daemon-reexec && "
            "systemctl --user daemon-reload && "
            "systemctl --user restart battery-monitor.service"
        )
        
        log.info(f"[BATTERY] Executing user systemd commands for {TARGET_USER}...")
        
        # We wrap it in 'sudo -u USER bash -c ...'
        r = run(["sudo", "-u", TARGET_USER, "bash", "-c", cmds], check=False, capture_output=True)
        
        if r.returncode == 0:
            log.info("[BATTERY] Service restarted successfully.")
        else:
            log.warning(f"[BATTERY] Service command failed (RC={r.returncode}).")
            log.warning(f"Stderr: {r.stderr}")
            log.warning("Note: The user might not have an active session yet.")

    except Exception as e:
        log.warning(f"[BATTERY] Failed to execute systemctl commands: {e}")


def set_executables_and_restart_i3():
    # chmod +x all scripts
    dirs = [
        USER_HOME / ".config" / "i3blocks" / "scripts",
        USER_HOME / ".config" / "rofi",
        USER_HOME / ".config" / "i3" / "scripts",
        USER_HOME / ".local" / "bin"
    ]
    for d in dirs:
        if d.exists():
            for f in d.rglob("*"):
                if f.is_file() and (f.suffix == ".sh" or d.name == "bin"):
                    try: f.chmod(0o755)
                    except: pass
    
    log.info("[i3] Restarting i3...")
    run(["sudo", "-u", TARGET_USER, "i3-msg", "restart"], check=False)

def apply_grub_theme(startup_dir: Path):
    log.info("[GRUB] Installing theme...")
    src = startup_dir / "grub"
    if src.exists():
        dst = Path("/boot/grub/themes/kali")
        shutil.rmtree(dst, ignore_errors=True)
        try: shutil.copytree(src, dst)
        except Exception as e: log.warning(f"Grub copy failed: {e}")

# ----------------------
# APP INSTALLERS
# ----------------------

# [EXPLAINER]
# To add a NEW APP installer:
# 1. Copy one of the functions below (like install_vscode).
# 2. Rename it (e.g., def install_obsidian():).
# 3. Replace the commands inside run([...]) with the commands needed to install that app.
#    (Usually 'wget ...' or 'apt install ...').

def install_telegram(startup_dir):
    log.info("[APP] Installing Telegram...")
    tfile = Path("/tmp/tsetup.tar.xz")
    run(["wget", "-q", "https://telegram.org/dl/desktop/linux", "-O", str(tfile)])
    opt = Path("/opt/Telegram")
    ensure_dir(opt)
    run(["tar", "-xf", str(tfile), "-C", str(opt), "--strip-components=1"])
    # Symlink
    link = Path("/usr/local/bin/telegram")
    if link.exists(): link.unlink()
    link.symlink_to(opt / "Telegram")

def install_brave_nightly():
    log.info("[APP] Installing Brave Nightly...")
    run('curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly bash', shell=True)
    run(["apt", "install", "-y", "brave-browser-nightly"])

def install_vscode():
    log.info("[APP] Installing VSCode...")
    deb = Path("/tmp/code.deb")
    run(["wget", "-q", "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64", "-O", str(deb)])
    run(["dpkg", "-i", str(deb)])
    run(["apt", "install", "-f", "-y"]) # Fix dependencies if needed

def install_protonvpn():
    log.info("[APP] Installing ProtonVPN...")
    deb = Path("/tmp/protonvpn.deb")
    url = "https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb"
    run(["wget", "-q", url, "-O", str(deb)])
    run(["dpkg", "-i", str(deb)])
    run(["apt", "update"])
    run(["apt", "install", "-y", "proton-vpn-gnome-desktop"])

def install_virtualbox():
    log.info("[APP] Installing VirtualBox...")
    run(["apt", "install", "-y", "virtualbox"])

def install_rustscan():
    log.info("[APP] Installing RustScan...")
    deb = Path("/tmp/rustscan.deb")
    url = "https://github.com/RustScan/RustScan/releases/download/2.2.3/rustscan_2.2.3_amd64.deb"
    run(["wget", "-q", url, "-O", str(deb)])
    run(["dpkg", "-i", str(deb)])
    run(["apt", "install", "-f", "-y"])

# [EXPLAINER]
# This is the new Spotify installer function.
# It adds the GPG key, adds the repo to sources list, updates apt, and installs.
def install_spotify():
    log.info("[APP] Installing Spotify...")
    # 1. Add GPG Key
    run("curl -sS https://download.spotify.com/debian/pubkey_6224F9941A8AA6D1.gpg | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg", shell=True)
    # 2. Add Repository
    run('echo "deb http://repository.spotify.com stable non-free" | tee /etc/apt/sources.list.d/spotify.list', shell=True)
    # 3. Update and Install
    run(["apt", "update"])
    run(["apt", "install", "-y", "spotify-client"])


# ----------------------
# INTERACTIVE MENU
# ----------------------
def prompt_yes_no(prompt: str) -> bool:
    while True:
        c = input(f"{prompt} [Y/n]: ").strip().lower()
        if c in ("", "y", "yes"): return True
        if c in ("n", "no"): return False

def prompt_multi_select() -> List[int]:
    # [EXPLAINER]
    # Update this text list if you added a new app to APP_OPTIONS above.
    print("\nSelect applications to install:")
    print(" 1) Telegram")
    print(" 2) Brave (Nightly)")
    print(" 3) VSCode")
    print(" 4) ProtonVPN")
    print(" 5) VirtualBox")
    print(" 6) RustScan")
    print(" 7) Spotify")  # <--- NEW
    print(" 8) All")
    print(" 9) None")
    
    raw = input("Enter choices (e.g. '1 3 7'): ").strip()
    if not raw: return []
    
    nums = []
    # logic to parse input
    parts = raw.replace(",", " ").split()
    for p in parts:
        if p.isdigit():
            val = int(p)
            if val == 8: return list(range(1, 8)) # All
            if val == 9: return []                # None
            if 1 <= val <= 7: nums.append(val)
    return nums

# ----------------------
# MAIN EXECUTION
# ----------------------
def main():
    require_root()
    startup_dir = detect_or_clone_repo()

    # 1. Install System Apt Packages
    install_apt_packages(APT_PACKAGES)

    # 2. Configs
    copy_core_configs(startup_dir)

    # 3. Battery Monitor (Modified command sequence)
    install_battery_monitor(startup_dir)

    # 4. Final Permissions & Reload
    set_executables_and_restart_i3()

    # 5. GRUB
    if prompt_yes_no("Apply GRUB theme?"):
        apply_grub_theme(startup_dir)

    # =========================================================================
    # [EXPLAINER] - HOW TO ADD CUSTOM COMMANDS
    # =========================================================================
    # If you have a specific command you need to run every time (like creating a 
    # folder, or setting a permission), uncomment the lines below (remove the #)
    # and edit the text inside the quotes.
    #
    # Example 1: Run a simple shell command
    # run("echo 'Hello World' > /tmp/hello.txt", shell=True)
    #
    # Example 2: Run a command as the user (not root)
    # run(["sudo", "-u", TARGET_USER, "mkdir", "-p", f"{USER_HOME}/Documents/MyWork"])
    #
    # Example 3: Install a python package
    # run(["pip3", "install", "requests"])
    # =========================================================================

    # 6. Interactive App Install
    selections = prompt_multi_select()
    for s in selections:
        if s == 1: install_telegram(startup_dir)
        elif s == 2: install_brave_nightly()
        elif s == 3: install_vscode()
        elif s == 4: install_protonvpn()
        elif s == 5: install_virtualbox()
        elif s == 6: install_rustscan()
        elif s == 7: install_spotify() # <--- Connects menu option 7 to the function

    log.info("[DONE] Setup complete!")

if __name__ == "__main__":
    main()
