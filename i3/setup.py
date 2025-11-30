#!/usr/bin/env python3
"""
startup_setup.py

Python conversion of your bash startup script.
Run with sudo/root:
    sudo python3 setup.py

Behavior:
- Detects if running inside startup repo; clones if not present.
- Installs packages (apt).
- Copies config files into user locations with backups.
- Installs apps (Telegram, Brave nightly, ProtonVPN, VSCode, RustScan).
- Applies grub theme files.
- Attempts to be idempotent and robust.
"""

from __future__ import annotations
import os
import sys
import shutil
import subprocess
import datetime
from pathlib import Path
import tempfile

# -------------------------
# Configuration constants
# -------------------------
REPO_URL = "https://github.com/Abr-ahamis/startup.git"
REPO_DIR_NAME = "startup"

APT_PACKAGES = [
    "i3-wm", "i3blocks", "rofi", "polkitd", "xdotool", "dex", "acpi", "upower",
    "xfce4-power-manager", "i3lock", "xss-lock", "pulseaudio-utils",
    "brightnessctl", "feh", "picom", "fonts-font-awesome", "git", "rsync",
    "unzip", "curl", "wget", "grub-customizer", "timeshift"
]

EXTRA_PACKAGES_AFTER = [
    # Some packages may be installed through .deb or external scripts; keep as fallback
]

USER_HOME = Path(os.path.expanduser("~"))
# If running as root, SUDO_USER will hold the original user; use that user's home
if os.environ.get("SUDO_USER"):
    USER = os.environ.get("SUDO_USER")
    USER_HOME = Path("/home") / USER if Path("/home").exists() else Path(os.path.expanduser("~"))
else:
    USER = os.environ.get("USER", USER)

STARTUP_BACKUP_ROOT = USER_HOME / ".config" / "startup-backups"

# -------------------------
# Utility helpers
# -------------------------
def die(msg: str, code: int = 1):
    print(f"[ERROR] {msg}", file=sys.stderr)
    sys.exit(code)

def run(cmd, check=False, capture_output=False, env=None):
    """Run shell command list or string (string runs in shell). Returns CompletedProcess."""
    if isinstance(cmd, (list, tuple)):
        print(f"[CMD] {' '.join(cmd)}")
    else:
        print(f"[CMD] {cmd}")
    try:
        if isinstance(cmd, (list, tuple)):
            return subprocess.run(cmd, check=check, capture_output=capture_output, text=True, env=env)
        else:
            return subprocess.run(cmd, check=check, capture_output=capture_output, text=True, shell=True, env=env)
    except subprocess.CalledProcessError as e:
        print(f"[CMD-FAIL] returncode={e.returncode} cmd={e.cmd}")
        if capture_output:
            print("stdout:", e.stdout)
            print("stderr:", e.stderr)
        if check:
            raise
        return e

def ensure_dir(p: Path, mode=0o755):
    if not p.exists():
        print(f"[MKDIR] {p}")
        p.mkdir(parents=True, mode=mode, exist_ok=True)

def backup_path(target: Path) -> Path:
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_dir = STARTUP_BACKUP_ROOT / ts
    ensure_dir(backup_dir)
    return backup_dir / target.name

def safe_copy(src: Path, dst: Path, make_backup=True, dirs_exist_ok=False):
    """
    Copy file or directory src -> dst.
    If dst exists and make_backup True, move existing dst to backup dir.
    """
    src = Path(src)
    dst = Path(dst)
    if not src.exists():
        print(f"[SKIP] Source does not exist: {src}")
        return False
    # If parent doesn't exist, create
    ensure_dir(dst.parent)
    if dst.exists():
        if make_backup:
            b = backup_path(dst)
            print(f"[BACKUP] Moving existing {dst} -> {b}")
            shutil.move(str(dst), str(b))
        else:
            if dst.is_dir():
                if dirs_exist_ok:
                    # we'll merge later by copying contents
                    pass
                else:
                    print(f"[REMOVE] Removing existing {dst}")
                    if dst.is_dir():
                        shutil.rmtree(dst)
                    else:
                        dst.unlink()
    # Copy
    if src.is_dir():
        print(f"[COPY-DIR] {src} -> {dst}")
        shutil.copytree(src, dst, dirs_exist_ok=dirs_exist_ok)
    else:
        print(f"[COPY-FILE] {src} -> {dst}")
        shutil.copy2(src, dst)
    return True

def safe_rm(path: Path):
    if path.exists():
        print(f"[RM] {path}")
        if path.is_dir():
            shutil.rmtree(path, ignore_errors=True)
        else:
            path.unlink()

# -------------------------
# Root check
# -------------------------
def require_root():
    if os.geteuid() != 0:
        die("This script must be run as root. Use sudo python3 startup_setup.py")

# -------------------------
# Main logic
# -------------------------
def detect_or_clone_repo() -> Path:
    cwd = Path.cwd()
    print(f"[INFO] Current working directory: {cwd}")
    # Case 1: We're already inside repo root (contains i3, grub, wallpaper)
    if (cwd / "i3").is_dir() and (cwd / "grub").is_dir() and (cwd / "wallpaper").is_dir():
        print("[INFO] Detected startup folder in current directory; using it.")
        return cwd
    # Case 2: There's ./startup folder here
    if (cwd / REPO_DIR_NAME).is_dir():
        print(f"[INFO] Found {REPO_DIR_NAME} subdirectory; using it.")
        return cwd / REPO_DIR_NAME
    # Otherwise clone into cwd/startup
    target = cwd / REPO_DIR_NAME
    if target.exists():
        print(f"[INFO] {target} exists (not directory?). Using it.")
        return target
    print(f"[INFO] Cloning {REPO_URL} -> {target}")
    r = run(["git", "clone", REPO_URL, str(target)], check=False)
    if r.returncode != 0:
        print("[WARN] git clone failed or returned non-zero (continue if repo already available).")
    return target

def apt_update_upgrade_and_install(pkgs):
    print("[APT] Updating package lists and upgrading packages (may take some time)...")
    run(["apt", "update"], check=False)
    run(["apt", "upgrade", "-y"], check=False)
    if pkgs:
        print(f"[APT] Installing packages: {' '.join(pkgs)}")
        run(["apt", "install", "-y"] + pkgs, check=False)

def install_fonts_and_update_cache():
    print("[FONTS] Updating font cache")
    run(["fc-cache", "-fv"], check=False)

def copy_core_configs(startup_dir: Path):
    # Paths inside repo
    print("[COPY] Copying core configuration files from repo to user's config locations.")
    repo_i3 = startup_dir / "i3"
    # i3 config
    src_i3_config = repo_i3 / ".config" / "i3" / "config"
    dst_i3_config = USER_HOME / ".config" / "i3" / "config"
    safe_copy(src_i3_config, dst_i3_config, make_backup=True)

    # i3blocks
    src_i3blocks = repo_i3 / ".config" / "i3blocks"
    dst_i3blocks = USER_HOME / ".config" / "i3blocks"
    safe_copy(src_i3blocks, dst_i3blocks, make_backup=True, dirs_exist_ok=True)

    # rofi
    src_rofi = repo_i3 / ".config" / "rofi"
    dst_rofi = USER_HOME / ".config" / "rofi"
    safe_copy(src_rofi, dst_rofi, make_backup=True, dirs_exist_ok=True)

    # picom
    src_picom = repo_i3 / ".config" / "picom" / "picom.conf"
    dst_picom = USER_HOME / ".config" / "picom" / "picom.conf"
    safe_copy(src_picom, dst_picom, make_backup=True)

    # local bin
    src_local_bin = repo_i3 / ".local" / "bin"
    dst_local_bin = USER_HOME / ".local" / "bin"
    ensure_dir(dst_local_bin)
    if src_local_bin.exists():
        for f in src_local_bin.iterdir():
            safe_copy(f, dst_local_bin / f.name, make_backup=True)

    # fonts
    src_fonts = repo_i3 / ".local" / "share" / "fonts"
    dst_fonts = USER_HOME / ".local" / "share" / "fonts"
    ensure_dir(dst_fonts)
    if src_fonts.exists():
        for f in src_fonts.iterdir():
            safe_copy(f, dst_fonts / f.name, make_backup=True)

    # rofi system themes
    # Some distros place system-wide polybar/rofi themes in /usr/share/...
    src_rofi_sys = repo_i3 / "usr" / "share" / "rofi" / "themes"
    dst_rofi_sys = Path("/usr/share/rofi/themes")
    ensure_dir(dst_rofi_sys)
    if src_rofi_sys.exists():
        for f in src_rofi_sys.iterdir():
            # copy with sudo already (we are root)
            safe_copy(f, dst_rofi_sys / f.name, make_backup=True)

    # wallpapers
    repo_wall = startup_dir / "wallpaper"
    dst_pics = USER_HOME / "Pictures"
    ensure_dir(dst_pics)
    for name in ("wallpaper.jpg", "wallpaper-1.jpg", "wallpaper-2.jpg"):
        s = repo_wall / name
        if s.exists():
            safe_copy(s, dst_pics / name, make_backup=True)
            # copy to system backgrounds for Kali (best-effort)
            sys_bg = Path("/usr/share/backgrounds/kali")
            ensure_dir(sys_bg)
            try:
                shutil.copy2(s, sys_bg / name)
            except Exception as e:
                print(f"[WARN] Could not copy {s} -> {sys_bg}: {e}")

def set_executables_and_restart_i3():
    # Make scripts executable
    scripts_dir = USER_HOME / ".config" / "i3blocks" / "scripts"
    if scripts_dir.exists():
        for sh in scripts_dir.glob("*.sh"):
            print(f"[CHMOD] +x {sh}")
            sh.chmod(0o755)
    # Rofi scripts
    rofi_dir = USER_HOME / ".config" / "rofi"
    if rofi_dir.exists():
        for f in rofi_dir.rglob("*.sh"):
            print(f"[CHMOD] +x {f}")
            f.chmod(0o755)
    # local bin
    local_bin = USER_HOME / ".local" / "bin"
    if local_bin.exists():
        for f in local_bin.iterdir():
            if f.is_file():
                f.chmod(0o755)

    # Try to restart i3 (best-effort)
    print("[I3] Attempting to restart i3 (i3-msg restart)...")
    run(["i3-msg", "restart"], check=False)

def apply_grub_theme(startup_dir: Path):
    print("[GRUB] Applying grub themes from repo.")
    repo_grub = startup_dir / "grub"
    dst_boot_grub = Path("/boot/grub/themes/kali")
    # safe remove existing
    if dst_boot_grub.exists():
        print(f"[GRUB] Removing existing {dst_boot_grub}")
        shutil.rmtree(dst_boot_grub, ignore_errors=True)
    # copy entire grub dir to /boot/grub/themes/kali
    try:
        shutil.copytree(repo_grub, dst_boot_grub)
        print(f"[GRUB] Copied {repo_grub} -> {dst_boot_grub}")
    except Exception as e:
        print(f"[WARN] Could not copy grub theme directory: {e}")

    # Also ensure in /usr/share/grub/themes
    dst_usr_share = Path("/usr/share/grub/themes")
    ensure_dir(dst_usr_share)
    try:
        # remove if exists
        if (dst_usr_share / "kali").exists():
            shutil.rmtree(dst_usr_share / "kali", ignore_errors=True)
        shutil.copytree(dst_boot_grub, dst_usr_share / "kali", dirs_exist_ok=True)
    except Exception as e:
        print(f"[WARN] Could not copy grub themes to {dst_usr_share}: {e}")

    # copy extra wallpapers into backgrounds (best-effort)
    repo_wall = startup_dir / "wallpaper"
    backgrounds_dir = Path("/usr/share/backgrounds/kali")
    ensure_dir(backgrounds_dir)
    for mapping in [
        ("wallpaper-1.jpg", "login.svg"),
        ("wallpaper.jpg", "kali-maze-16x9.jpg"),
        ("wallpaper-2.jpg", "kali-tiles-16x9.jpg"),
        ("wallpaper-1.jpg", "kali-waves-16x9.png"),
        ("wallpaper.jpg", "kali-oleo-16x9.png"),
        ("wallpaper-2.jpg", "kali-tiles-purple-16x9.jpg"),
    ]:
        src_name, dst_name = mapping
        s = repo_wall / src_name
        if s.exists():
            try:
                shutil.copy2(s, backgrounds_dir / dst_name)
            except Exception as e:
                print(f"[WARN] Could not copy {s} -> {backgrounds_dir}/{dst_name}: {e}")

def install_telegram(startup_dir: Path):
    print("[TELEGRAM] Installing Telegram (desktop tarball).")
    tmp = Path("/tmp")
    tfile = tmp / "tsetup.tar.xz"
    # download
    run(["wget", "-q", "https://telegram.org/dl/desktop/linux", "-O", str(tfile)], check=False)
    opt_telegram = Path("/opt/Telegram")
    if opt_telegram.exists():
        shutil.rmtree(opt_telegram, ignore_errors=True)
    ensure_dir(opt_telegram)
    # extract
    try:
        run(["tar", "-xf", str(tfile), "-C", str(opt_telegram), "--strip-components=1"], check=False)
        # make executable and symlink
        tbin = opt_telegram / "Telegram"
        if tbin.exists():
            tbin.chmod(0o755)
            run(["ln", "-sf", str(tbin), "/usr/local/bin/telegram-desktop"], check=False)
        else:
            print("[WARN] Telegram binary not found after extraction.")
    except Exception as e:
        print(f"[WARN] Telegram extraction/install failed: {e}")

    # Note: launching GUI app from root session may be inappropriate; skipping auto-launch.

def install_brave_nightly():
    print("[BRAVE] Installing Brave (nightly) via upstream install script (best-effort).")
    # download and run Brave install script with CHANNEL=nightly
    try:
        run('curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly bash', check=False, capture_output=False)
        # then try apt install
        run(["apt", "install", "-y", "brave-browser-nightly"], check=False)
    except Exception as e:
        print(f"[WARN] Brave install failed: {e}")

def set_gsettings_favorites():
    # Add brave .desktop to GNOME favorites if present (best-effort)
    print("[GSETTINGS] Attempting to add Brave to GNOME favorites (if GNOME present).")
    candidate_entries = ["brave-browser.desktop", "brave-browser-nightly.desktop", "brave.desktop"]
    desktop_to_add = None
    for entry in candidate_entries:
        if Path("/usr/share/applications", entry).exists():
            desktop_to_add = entry
            break
    if not desktop_to_add:
        print("[GSETTINGS] No brave desktop file found; skipping gsettings step.")
        return
    # get current favorites
    try:
        cp = run(["gsettings", "get", "org.gnome.shell", "favorite-apps"], capture_output=True)
        favs = cp.stdout.strip() if cp and cp.stdout else "[]"
        if desktop_to_add in favs:
            print(f"[GSETTINGS] {desktop_to_add} already in favorites.")
            return
        # Append
        # This sed style operation is replicated in Python
        new = favs.rstrip()
        if new.endswith("]"):
            new = new[:-1] + (", '%s']" % desktop_to_add)
        else:
            new = f"[{desktop_to_add}]"
        run(["gsettings", "set", "org.gnome.shell", "favorite-apps", new], check=False)
        print(f"[GSETTINGS] Added {desktop_to_add} to favorites.")
    except Exception as e:
        print(f"[WARN] gsettings step failed: {e}")

def install_protonvpn():
    print("[PROTONVPN] Attempting to download and install ProtonVPN repo package (best-effort).")
    tmp = Path("/tmp")
    deb = tmp / "protonvpn.deb"
    url = "https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb"
    run(["wget", "-q", url, "-O", str(deb)], check=False)
    if deb.exists():
        run(["dpkg", "-i", str(deb)], check=False)
        # apt update and install package
        run(["apt", "update"], check=False)
        # fix broken deps and attempt install
        run(["apt", "install", "-f", "-y"], check=False)
        # try to install the gui package (may vary by repo)
        run(["apt", "install", "-y", "proton-vpn-gnome-desktop"], check=False)

def install_vscode():
    print("[VSCODE] Installing VSCode (.deb) (best-effort).")
    tmp = Path("/tmp")
    deb = tmp / "code.deb"
    url = "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
    run(["wget", "-q", url, "-O", str(deb)], check=False)
    if deb.exists():
        r = run(["dpkg", "-i", str(deb)], check=False)
        if r.returncode != 0:
            run(["apt", "install", "-f", "-y"], check=False)
        try:
            deb.unlink()
        except Exception:
            pass

def install_rustscan():
    print("[RUSTSCAN] Installing RustScan deb (best-effort).")
    tmp = Path("/tmp")
    deb = tmp / "rustscan_2.2.3_amd64.deb"
    url = "https://github.com/RustScan/RustScan/releases/download/2.2.3/rustscan_2.2.3_amd64.deb"
    run(["wget", "-q", url, "-O", str(deb)], check=False)
    if deb.exists():
        r = run(["dpkg", "-i", str(deb)], check=False)
        if r.returncode != 0:
            run(["apt", "install", "-f", "-y"], check=False)
    # try adjust ulimit for current process (non-persistent)
    try:
        import resource
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        new_soft = max(soft, 5000)
        resource.setrlimit(resource.RLIMIT_NOFILE, (new_soft, hard))
        print(f"[ULIMIT] set RLIMIT_NOFILE soft={new_soft} hard={hard}")
    except Exception as e:
        print("[WARN] Could not set ulimit:", e)

def finalize():
    # run font cache
    install_fonts_and_update_cache()
    print("[FINAL] Done. Setup complete (errors may have been reported above).")

def main():
    require_root()
    startup_dir = detect_or_clone_repo()
    print(f"[USING] startup directory: {startup_dir}")

    # Create backup root
    ensure_dir(STARTUP_BACKUP_ROOT)

    # Update and install core packages
    apt_update_upgrade_and_install(APT_PACKAGES)

    # Ensure user config directories exist
    ensure_dir(USER_HOME / ".config" / "i3")
    ensure_dir(USER_HOME / ".config" / "i3blocks" / "scripts")
    ensure_dir(USER_HOME / ".config" / "rofi")
    ensure_dir(USER_HOME / ".config" / "picom")
    ensure_dir(USER_HOME / ".local" / "bin")
    ensure_dir(USER_HOME / ".local" / "share" / "fonts")
    ensure_dir(USER_HOME / "Pictures")
    ensure_dir(Path("/usr/share/rofi/themes"))

    # Copy files from repo to user/system locations
    copy_core_configs(startup_dir)

    # Set permissions and restart i3
    set_executables_and_restart_i3()

    # Grub
    apply_grub_theme(startup_dir)

    # Install apps
    install_telegram(startup_dir)
    install_brave_nightly()
    set_gsettings_favorites()
    install_protonvpn()
    install_vscode()
    install_rustscan()

    # extra apt installs (if any)
    if EXTRA_PACKAGES_AFTER:
        apt_update_upgrade_and_install(EXTRA_PACKAGES_AFTER)

    finalize()
    print("🎉 Setup script finished (check logs above).")

if __name__ == "__main__":
    main()
