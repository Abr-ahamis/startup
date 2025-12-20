#!/usr/bin/env python3
"""
startup_setup_full.py

Purpose:
  - Clone/detect a "startup" repo (contains i3, rofi, picom, i3blocks, wallpaper, grub, etc.)
  - Install required apt packages first (non-interactive)
  - Carefully backup existing config files (append .backup, add timestamp if needed)
  - Copy repo configuration files into the correct user locations
  - Ensure ~/.local/bin is present and in the user's PATH (.bashrc update)
  - Make scripts executable and restart i3 (as the user)
  - Optionally apply GRUB theme
  - Interactive multi-select menu to install apps (Telegram, Brave nightly, VSCode, ProtonVPN, VirtualBox, RustScan)
  - After Telegram install, create a symlink so user can run `telegram` from terminal (no full path)
  - Detailed, safe error handling and informative logging

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
from pathlib import Path
from typing import List, Optional
import pwd
import grp

# ----------------------
# CONFIG
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

# Apps offered in interactive menu
APP_OPTIONS = {
    1: "telegram",
    2: "brave-nightly",
    3: "vscode",
    4: "protonvpn",
    5: "virtualbox",
    6: "rustscan",
}

# ----------------------
# Logging
# ----------------------
logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
log = logging.getLogger("startup_setup")

# ----------------------
# Environment and user detection
# ----------------------
def get_target_user() -> str:
    """
    If run under sudo, SUDO_USER is the non-root user that invoked sudo.
    Otherwise, fallback to USER env (may be root).
    """
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
# Utilities
# ----------------------
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
      - shell: if True, run via shell (useful for complex commands)
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
    """
    Return a backup path with '.backup' appended. If that exists, append timestamp.
    Examples:
      ~/.config/i3/config -> ~/.config/i3/config.backup
      if exists -> config.backup.20251220-123456
    """
    base = p.with_name(p.name + ".backup")
    if not base.exists():
        return base
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    return p.with_name(p.name + f".backup.{ts}")


def backup_existing(dst: Path) -> Optional[Path]:
    """
    If dst exists, rename to dst.backup (or dst.backup.TIMESTAMP if needed).
    Returns new backup path or None if nothing was backed up.
    """
    try:
        if not dst.exists():
            return None
        b = unique_backup_name(dst)
        log.info(f"[BACKUP] Renaming existing {dst} -> {b}")
        # Use shutil.move for directories and files
        shutil.move(str(dst), str(b))
        return b
    except Exception as e:
        log.warning(f"[WARN] Failed to backup {dst}: {e}")
        return None


def chown_recursive(path: Path, user: str):
    """
    Change ownership of path (file or directory) recursively to 'user'.
    """
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
    """
    Copy src -> dst with safety:
      - if src doesn't exist: skip and return False
      - ensure dst.parent exists
      - if dst exists and make_backup=True: rename existing to .backup
      - for directories use copytree (dirs_exist_ok available on py3.8+)
      - preserve file metadata where possible
      - set ownership to target user
    """
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
            # remove existing if not backing up
            if dst.is_dir():
                log.info(f"[RM-EXIST] Removing existing dir {dst}")
                shutil.rmtree(dst, ignore_errors=True)
            else:
                log.info(f"[RM-EXIST] Removing existing file {dst}")
                try:
                    dst.unlink()
                except Exception:
                    pass
    try:
        if src.is_dir():
            log.info(f"[COPY-DIR] {src} -> {dst}")
            # copytree with dirs_exist_ok if available
            shutil.copytree(src, dst, dirs_exist_ok=dirs_exist_ok)
        else:
            log.info(f"[COPY-FILE] {src} -> {dst}")
            shutil.copy2(src, dst)
        # Ensure ownership is set to the target user for copied files
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
    # If i3 and grub and wallpaper exist here -> treat cwd as repo
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
    r = run(["git", "clone", REPO_URL, str(target)], check=False, capture_output=False)
    if isinstance(r, subprocess.CalledProcessError) or getattr(r, "returncode", 0) != 0:
        log.warning("[WARN] git clone returned non-zero; continuing in case repo exists locally.")
    return target


# ----------------------
# APT package installation
# ----------------------
def install_apt_packages(packages: List[str]):
    """
    Install packages with apt non-interactively. Runs apt update first.
    Uses DEBIAN_FRONTEND=noninteractive to minimize prompts, and
    sets PATH/ENV minimally for safety.
    """
    if not packages:
        log.info("[APT] No packages to install.")
        return
    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    # update
    log.info("[APT] Running apt update...")
    run(["apt", "update"], check=False, env=env)
    # install in one command
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
    # i3blocks directory
    safe_copy(repo_i3 / ".config" / "i3blocks", USER_HOME / ".config" / "i3blocks", make_backup=True, dirs_exist_ok=True)
    # rofi
    safe_copy(repo_i3 / ".config" / "rofi", USER_HOME / ".config" / "rofi", make_backup=True, dirs_exist_ok=True)
    # picom
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
    # Also update current process env so subsequent operations see it
    os.environ["PATH"] = str(USER_HOME / ".local" / "bin") + ":" + os.environ.get("PATH", "")

    # system rofi themes
    src_rofi_sys = repo_i3 / "usr" / "share" / "rofi" / "themes"
    dst_rofi_sys = Path("/usr/share/rofi/themes")
    ensure_dir(dst_rofi_sys)
    if src_rofi_sys.exists():
        for f in sorted(src_rofi_sys.iterdir()):
            safe_copy(f, dst_rofi_sys / f.name, make_backup=True)

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
# Make scripts executable and restart i3 (as the user)
# ----------------------
def set_executables_and_restart_i3():
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
    local_bin = USER_HOME / ".local" / "bin"
    if local_bin.exists():
        for f in local_bin.iterdir():
            if f.is_file():
                try:
                    f.chmod(0o755)
                except Exception:
                    pass
    # Attempt to restart i3 as the target user (non-fatal if it fails)
    try:
        run(["sudo", "-u", TARGET_USER, "i3-msg", "restart"], check=False)
    except Exception as e:
        log.warning(f"[WARN] Could not restart i3: {e}")


# ----------------------
# Apply GNOME Terminal profile settings (as the user)
# ----------------------
def apply_terminal_profile_settings():
    """
    Apply terminal settings using gsettings as the target user.
    This runs a small bash snippet via sudo -u to ensure commands run in the user's session.
    Note: gsettings may require a running X/Wayland session; if not available this will warn but continue.
    """
    # Build a bash snippet that gets the default profile ID and applies settings
    # Use single-quoted bash snippet and run via sudo -u TARGET_USER bash -lc '...'
    snippet = r"""
PROFILE=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d \')
if [ -n "$PROFILE" ]; then
  gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE/" default-show-menubar false || true
  gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE/" font 'Monospace 9' || true
  gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE/" use-transparent-background true || true
  gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE/" background-transparency-percent 20 || true
fi
"""
    log.info("[TERMINAL] Attempting to apply GNOME Terminal profile settings (best-effort).")
    try:
        run(["sudo", "-u", TARGET_USER, "bash", "-lc", snippet], check=False)
    except Exception as e:
        log.warning(f"[WARN] Terminal profile settings failed: {e}")


# ----------------------
# GRUB theme apply (best-effort)
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

    # wallpapers mapping for grub backgrounds (best-effort)
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
            try:
                shutil.copy2(s, backgrounds_dir / dst_name)
            except Exception as e:
                log.warning(f"[WARN] Could not copy {s} -> {backgrounds_dir}/{dst_name}: {e}")


# ----------------------
# App installers
# ----------------------
def install_telegram(startup_dir: Optional[Path] = None):
    """
    Install Telegram desktop to /opt/Telegram and create a symlink /usr/local/bin/telegram
    so the user can run `telegram` (lowercase) from terminal. Make symlink atomic and overwrite safely.
    """
    log.info("[TELEGRAM] Installing Telegram (tarball) — best-effort.")
    tfile = Path("/tmp/tsetup.tar.xz")
    # Download
    run(["wget", "-q", "https://telegram.org/dl/desktop/linux", "-O", str(tfile)], check=False)
    opt = Path("/opt/Telegram")
    # Remove existing opt dir (backup if present)
    if opt.exists():
        backup_existing(opt)
    ensure_dir(opt)
    # Extract into /opt/Telegram
    r = run(["tar", "-xf", str(tfile), "-C", str(opt), "--strip-components=1"], check=False)
    tbin = opt / "Telegram"
    if tbin.exists():
        try:
            tbin.chmod(0o755)
        except Exception:
            pass
        # Create symlink so any user can run 'telegram' from PATH
        ensure_dir(Path("/usr/local/bin"))
        try:
            link = Path("/usr/local/bin/telegram")
            # Remove existing link/file if present
            if link.exists() or link.is_symlink():
                try:
                    link.unlink()
                except Exception:
                    pass
            link.symlink_to(tbin)
            log.info(f"[TELEGRAM] Created symlink {link} -> {tbin}")
        except Exception as e:
            log.warning(f"[WARN] Could not create symlink for telegram: {e}")
        # Optionally make a user-level desktop file or other integration (left as future enhancement)
    else:
        log.warning("[WARN] Telegram binary not found after extraction.")


def install_brave_nightly():
    log.info("[BRAVE] Installing Brave (nightly) — best-effort.")
    run('curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly bash', check=False, shell=True)
    run(["apt", "install", "-y", "brave-browser-nightly"], check=False)


def install_vscode():
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


def install_protonvpn():
    log.info("[PROTONVPN] Installing ProtonVPN repo package (best-effort).")
    deb = Path("/tmp/protonvpn.deb")
    url = "https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb"
    run(["wget", "-q", url, "-O", str(deb)], check=False)
    if deb.exists():
        run(["dpkg", "-i", str(deb)], check=False)
        run(["apt", "update"], check=False)
        run(["apt", "install", "-f", "-y"], check=False)
        run(["apt", "install", "-y", "proton-vpn-gnome-desktop"], check=False)


def install_virtualbox():
    log.info("[VBOX] Installing VirtualBox (from apt) — best-effort.")
    run(["apt", "update"], check=False)
    run(["apt", "install", "-y", "virtualbox"], check=False)


def install_rustscan():
    log.info("[RUSTSCAN] Installing RustScan (.deb) — best-effort.")
    deb = Path("/tmp/rustscan_2.2.3_amd64.deb")
    url = "https://github.com/RustScan/RustScan/releases/download/2.2.3/rustscan_2.2.3_amd64.deb"
    run(["wget", "-q", url, "-O", str(deb)], check=False)
    if deb.exists():
        r = run(["dpkg", "-i", str(deb)], check=False)
        if getattr(r, "returncode", 0) != 0:
            run(["apt", "install", "-f", "-y"], check=False)
    # Attempt to raise file descriptor limit for RustScan runtime (best-effort)
    try:
        import resource
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        new_soft = max(soft, 5000)
        resource.setrlimit(resource.RLIMIT_NOFILE, (new_soft, hard))
        log.info(f"[ULIMIT] set RLIMIT_NOFILE soft={new_soft} hard={hard}")
    except Exception as e:
        log.warning(f"[WARN] Could not adjust ulimit: {e}")


# ----------------------
# Interactive prompts
# ----------------------
def prompt_yes_no(prompt: str, default: str = "y") -> bool:
    default = default.lower()
    yn = "[Y/n]" if default == "y" else "[y/N]"
    while True:
        choice = input(f"{prompt} {yn}: ").strip().lower()
        if choice == "" and default:
            return default == "y"
        if choice in ("y", "yes"):
            return True
        if choice in ("n", "no"):
            return False
        print("Please answer 'y' or 'n'.")


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
    raw = input("Enter selection (e.g. '1 3 5' or '7' for All): ").strip()
    if not raw:
        log.info("[INPUT] No selection entered; assuming 'None'.")
        return []
    tokens = []
    for part in raw.replace(",", " ").split():
        if part.isdigit():
            tokens.append(int(part))
        else:
            partl = part.lower()
            if partl in ("all", "7"):
                return list(range(1, 7))
            if partl in ("none", "0", "8"):
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
    # 1) Clone or detect repo
    startup_dir = detect_or_clone_repo()

    # 2) Install system packages first
    install_apt_packages(APT_PACKAGES)

    # 3) Copy configs from repo into user's home (backups made)
    copy_core_configs(startup_dir)

    # 4) Ensure scripts are executable and restart i3 (as user)
    set_executables_and_restart_i3()

    # 5) Apply terminal profile settings last among config changes
    apply_terminal_profile_settings()

    # 6) Optional GRUB theme
    if prompt_yes_no("Do you want to apply GRUB theme?"):
        apply_grub_theme(startup_dir)

    # 7) Interactive app installation
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

    log.info("[DONE] Setup complete!")


if __name__ == "__main__":
    main()
