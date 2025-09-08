#!/usr/bin/env python3
"""
install_startup.py — robust, error-checked version
Run with sudo:
sudo python3 install_startup.py
"""

import os
import sys
import subprocess
import shutil
import logging
import urllib.request
import urllib.error
import re
import time
import hashlib
import resource
from urllib.parse import urlparse

# -------------------------
# Configuration
# -------------------------
REPO_URL = "https://github.com/Abr-ahamis/startup.git"
REPO_DIRNAME = "startup"
DOWNLOADS_DIRNAME = "downloads"

# Direct links/pages
VSCODE_DEB_URL = "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
TELEGRAM_DL_PAGE = "https://telegram.org/dl/desktop/linux"
BRAVE_INSTALLER_URL = "https://dl.brave.com/install.sh"
PROTONVPN_DEB_URL = "https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb"
# ProtonVPN SHA256 as provided
PROTONVPN_SHA256 = "0b14e71586b22e498eb20926c48c7b434b751149b1f2af9902ef1cfe6b03e180"
RUSTSCAN_DEB_URL = "https://github.com/RustScan/RustScan/releases/download/2.2.3/rustscan_2.2.3_amd64.deb"

# Repo resources expected
GRUB_CFG_SRC = "grub.cfg"
KALI_THEME_SRC = "kali"
WALLPAPER_DIR = "wallpaper"
WALLPAPER_FILES = [
    ("20-wallpaper.svg", "/usr/share/backgrounds/kali/login.svg"),
    ("12-wallpaper.png", "/usr/share/backgrounds/kali/kali-maze-16x9.jpg"),
    ("1-wallpaper.png", "/usr/share/backgrounds/kali/kali-tiles-16x9.jpg"),
    ("2-wallpaper.png", "/usr/share/backgrounds/kali/kali-waves-16x9.png"),
    ("3-wallpaper.png", "/usr/share/backgrounds/kali/kali-oleo-16x9.png"),
    ("4-wallpaper.png", "/usr/share/backgrounds/kali/kali-tiles-purple-16x9.jpg"),
]
WALLPAPER_FILES_TO_BACKUP = [
    "kali-maze-16x9.jpg",
    "kali-tiles-16x9.jpg",
    "kali-oleo-16x9.png",
    "kali-tiles-purple-16x9.jpg",
    "kali-waves-16x9.png",
    "login.svg",
    "login-blurred",
]

# Desired font to set
DESIRED_FONT_FAMILY = "DejaVu Serif Condensed"
DESIRED_FONT_PACKAGE = "fonts-dejavu-core"
DESIRED_FONT_SETTING = f"{DESIRED_FONT_FAMILY} 10"

# -------------------------
# Logging
# -------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("installer")

# -------------------------
# Helpers
# -------------------------
def run_cmd(cmd, check=True, capture_output=False, env=None):
    """Run command; if capture_output True returns (proc, stdout, stderr)."""
    display = " ".join(cmd) if isinstance(cmd, (list, tuple)) else str(cmd)
    logger.info(f"Running: {display}")
    try:
        proc = subprocess.run(
            cmd,
            shell=isinstance(cmd, str),
            check=check,
            stdout=subprocess.PIPE if capture_output else None,
            stderr=subprocess.PIPE if capture_output else None,
            env=env,
        )
        if capture_output:
            out = proc.stdout.decode(errors="ignore") if proc.stdout else ""
            err = proc.stderr.decode(errors="ignore") if proc.stderr else ""
            logger.debug(f"stdout: {out}")
            logger.debug(f"stderr: {err}")
            return proc, out, err
        return proc
    except subprocess.CalledProcessError as e:
        logger.error(f"Command failed: {display} (exit {getattr(e,'returncode', 'unknown')})")
        if capture_output:
            out = e.stdout.decode(errors="ignore") if getattr(e, "stdout", None) else ""
            err = e.stderr.decode(errors="ignore") if getattr(e, "stderr", None) else ""
            logger.error(f"stdout: {out}")
            logger.error(f"stderr: {err}")
        raise


def require_root():
    if os.geteuid() != 0:
        logger.error("This script must be run as root (sudo). Exiting.")
        sys.exit(2)


def safe_makedirs(path, mode=0o755):
    os.makedirs(path, exist_ok=True)
    try:
        os.chmod(path, mode)
    except Exception:
        pass


def make_unique_path(path_base):
    """Return path_base or a timestamped unique variant if exists."""
    if not os.path.exists(path_base):
        return path_base
    timestamp = int(time.time())
    candidate = f"{path_base}.{timestamp}"
    counter = 0
    while os.path.exists(candidate):
        counter += 1
        candidate = f"{path_base}.{timestamp}.{counter}"
    return candidate


def sha256_of_file(path, chunk_size=8192):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(chunk_size), b""):
            h.update(chunk)
    return h.hexdigest()


def download_with_retries(url, target_path, retries=3, timeout=30, user_agent=None):
    """
    Download a URL to target_path with retries. Returns target_path on success.
    Raises on final failure.
    """
    if user_agent is None:
        user_agent = "Mozilla/5.0 (X11; Linux x86_64) InstallerScript/1.0"
    headers = {"User-Agent": user_agent}
    for attempt in range(1, retries + 1):
        try:
            logger.info(f"Downloading (attempt {attempt}/{retries}): {url}")
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                # stream to file
                safe_makedirs(os.path.dirname(target_path) or ".")
                with open(target_path, "wb") as fh:
                    while True:
                        chunk = resp.read(8192)
                        if not chunk:
                            break
                        fh.write(chunk)
            logger.info(f"Saved to: {target_path}")
            return target_path
        except urllib.error.HTTPError as e:
            logger.warning(f"HTTP error downloading {url}: {e.code} {e.reason}")
            last_err = e
        except urllib.error.URLError as e:
            logger.warning(f"URL error downloading {url}: {e.reason}")
            last_err = e
        except Exception as e:
            logger.warning(f"Error downloading {url}: {e}")
            last_err = e
        time.sleep(1 + attempt)
    logger.error(f"Failed to download {url} after {retries} attempts")
    raise last_err


# -------------------------
# Main steps
# -------------------------
def clone_repo(repo_url, dest_dir):
    if os.path.isdir(dest_dir):
        logger.info(f"Repo directory '{dest_dir}' exists; attempting git pull.")
        try:
            run_cmd(["git", "-C", dest_dir, "pull"])
            return
        except Exception:
            logger.warning("git pull failed; renaming existing directory and cloning fresh.")
            backup_name = f"{dest_dir}.bak-{int(time.time())}"
            shutil.move(dest_dir, backup_name)
            logger.info(f"Moved existing repo to {backup_name}")
    run_cmd(["git", "clone", repo_url, dest_dir])


def setup_downloads(repo_path):
    downloads = os.path.join(repo_path, DOWNLOADS_DIRNAME)
    safe_makedirs(downloads)
    logger.info(f"Downloads folder: {downloads}")
    return downloads


def backup_and_copy_grub(repo_path):
    logger.info("Backing up and copying GRUB themes and grub.cfg")
    grub_cfg_path = "/boot/grub/grub.cfg"
    if os.path.exists(grub_cfg_path):
        dest = make_unique_path(grub_cfg_path + ".b")
        logger.info(f"Moving {grub_cfg_path} -> {dest}")
        shutil.move(grub_cfg_path, dest)
    src_grubcfg = os.path.join(repo_path, GRUB_CFG_SRC)
    if not os.path.exists(src_grubcfg):
        raise FileNotFoundError(f"{src_grubcfg} not found in repo")
    safe_makedirs("/boot/grub")
    shutil.copy(src_grubcfg, "/boot/grub/")
    safe_makedirs("/boot/grub/themes/backup")
    safe_makedirs("/usr/share/grub/themes/backup")

    boot_kali = "/boot/grub/themes/kali"
    if os.path.isdir(boot_kali):
        dest = make_unique_path("/boot/grub/themes/backup/kali.b")
        logger.info(f"Moving existing {boot_kali} -> {dest}")
        shutil.move(boot_kali, dest)

    repo_kali = os.path.join(repo_path, KALI_THEME_SRC)
    if not os.path.isdir(repo_kali):
        raise FileNotFoundError(f"{repo_kali} not found in repo")
    safe_makedirs("/boot/grub/themes")
    shutil.copytree(repo_kali, "/boot/grub/themes/kali", dirs_exist_ok=True)

    usr_kali = "/usr/share/grub/themes/kali"
    if os.path.isdir(usr_kali):
        dest = make_unique_path("/usr/share/grub/themes/backup/kali.b")
        logger.info(f"Backing up {usr_kali} -> {dest}")
        shutil.move(usr_kali, dest)
    safe_makedirs("/usr/share/grub/themes")
    shutil.copytree("/boot/grub/themes/kali", "/usr/share/grub/themes/kali", dirs_exist_ok=True)


def backup_and_copy_wallpapers(repo_path):
    logger.info("Backing up and copying wallpapers")
    wallpaper_repo_path = os.path.join(repo_path, WALLPAPER_DIR)
    if not os.path.isdir(wallpaper_repo_path):
        raise FileNotFoundError(f"{wallpaper_repo_path} not found in repo")

    target_dir = "/usr/share/backgrounds/kali"
    backup_dir = os.path.join(target_dir, "backup")
    safe_makedirs(backup_dir)

    for f in WALLPAPER_FILES_TO_BACKUP:
        target_file = os.path.join(target_dir, f)
        if os.path.exists(target_file):
            dest = make_unique_path(os.path.join(backup_dir, f + ".b"))
            safe_makedirs(os.path.dirname(dest))
            shutil.move(target_file, dest)
            logger.info(f"Backed up {target_file} -> {dest}")

    for src_name, dest in WALLPAPER_FILES:
        src_file = os.path.join(wallpaper_repo_path, src_name)
        if not os.path.exists(src_file):
            raise FileNotFoundError(f"{src_file} not found in repo")
        safe_makedirs(os.path.dirname(dest))
        shutil.copy(src_file, dest)
        logger.info(f"Copied {src_file} -> {dest}")


def ensure_font_available(font_family, apt_package=DESIRED_FONT_PACKAGE):
    try:
        proc = subprocess.run(["fc-list", ":family"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        out = proc.stdout.decode(errors="ignore")
        if font_family.lower() in out.lower():
            logger.info(f"Font '{font_family}' already available.")
            return True
    except FileNotFoundError:
        logger.debug("fc-list not available; will attempt apt install of font package.")

    try:
        run_cmd(["apt-get", "update"])
        run_cmd(["apt-get", "install", "-y", apt_package])
    except Exception as e:
        logger.warning(f"Could not install font package {apt_package}: {e}")

    try:
        proc2 = subprocess.run(["fc-list", ":family"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        out2 = proc2.stdout.decode(errors="ignore")
        if font_family.lower() in out2.lower():
            logger.info(f"Font '{font_family}' installed/available.")
            return True
    except Exception:
        pass

    logger.warning(f"Font '{font_family}' not found after attempts.")
    return False


def apply_gnome_tweaks():
    logger.info("Applying GNOME tweaks and font settings")
    ensure_font_available(DESIRED_FONT_FAMILY, apt_package=DESIRED_FONT_PACKAGE)
    try:
        run_cmd(["gsettings", "set", "org.gnome.desktop.interface", "font-name", DESIRED_FONT_SETTING])
        logger.info(f"Set interface font -> {DESIRED_FONT_SETTING}")
    except Exception as e:
        logger.warning(f"Failed to set interface font: {e}")
    try:
        run_cmd(["gsettings", "set", "org.gnome.desktop.interface", "text-scaling-factor", "0.95"])
        run_cmd(["gsettings", "set", "org.gnome.desktop.background", "picture-options", "zoom"])
    except Exception as e:
        logger.warning(f"Failed to set some gsettings: {e}")
    # Read back
    try:
        _, font_out, _ = run_cmd(["gsettings", "get", "org.gnome.desktop.interface", "font-name"], capture_output=True)
        _, scale_out, _ = run_cmd(["gsettings", "get", "org.gnome.desktop.interface", "text-scaling-factor"], capture_output=True)
        _, pic_out, _ = run_cmd(["gsettings", "get", "org.gnome.desktop.background", "picture-options"], capture_output=True)
        logger.info("GNOME settings now:")
        logger.info(font_out.strip())
        logger.info(scale_out.strip())
        logger.info(pic_out.strip())
    except Exception:
        logger.debug("Could not read back gsettings values.")


def configure_dash_to_dock():
    logger.info("Configuring Dash-to-Dock")
    cmds = [
        ["gsettings", "set", "org.gnome.shell.extensions.dash-to-dock", "dock-position", "LEFT"],
        ["gsettings", "set", "org.gnome.shell.extensions.dash-to-dock", "autohide", "true"],
        ["gsettings", "set", "org.gnome.shell.extensions.dash-to-dock", "animation-time", "0.0"],
        ["gsettings", "set", "org.gnome.shell.extensions.dash-to-dock", "hide-delay", "0.0"],
        ["gsettings", "set", "org.gnome.shell.extensions.dash-to-dock", "pressure-threshold", "0.0"],
        ["gsettings", "set", "org.gnome.shell.extensions.dash-to-dock", "dash-max-icon-size", "20"],
    ]
    for c in cmds:
        run_cmd(c)
    keys = ["dock-position", "autohide", "animation-time", "hide-delay", "pressure-threshold", "dash-max-icon-size"]
    for k in keys:
        _, out, _ = run_cmd(["gsettings", "get", "org.gnome.shell.extensions.dash-to-dock", k], capture_output=True)
        logger.info(f"{k}: {out.strip()}")


def install_telegram(downloads_dir):
    logger.info("Installing Telegram Desktop (saved into downloads folder)")
    # Try following redirect first
    try:
        req = urllib.request.Request(TELEGRAM_DL_PAGE, headers={"User-Agent": "Installer/1.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            final_url = resp.geturl()
            page = resp.read().decode(errors="ignore")
    except Exception as e:
        logger.warning(f"Could not fetch Telegram page: {e}")
        final_url = None
        page = ""

    tg_url = None
    # If redirect gave direct tar.xz
    if final_url and final_url.endswith(".tar.xz"):
        tg_url = final_url
        logger.info(f"Redirected to Telegram archive: {tg_url}")
    else:
        # Search for tsetup link in HTML
        m = re.search(r"https://telegram\.org/dl/desktop/linux/tsetup\.[0-9]+\.[0-9]+\.[0-9]+\.tar\.xz", page)
        if m:
            tg_url = m.group(0)
            logger.info(f"Found Telegram link in page: {tg_url}")
    # fallback any .tar.xz in page
    if not tg_url and page:
        m2 = re.search(r"https://[^\s'\"<>]+\.tar\.xz", page)
        if m2:
            tg_url = m2.group(0)
            logger.info(f"Fallback found .tar.xz link: {tg_url}")

    if not tg_url:
        # Last attempt: sometimes telegram provides stable named link; attempt a small set of plausible names (non-exhaustive)
        # NOTE: keeping this list short avoids stale hardcoding; these are reasonable fallbacks
        candidates = [
            "https://telegram.org/dl/desktop/linux/tsetup.4.9.12.tar.xz",
            "https://telegram.org/dl/desktop/linux/tsetup.4.9.11.tar.xz",
        ]
        for c in candidates:
            try:
                # HEAD-like attempt by opening with small timeout
                req2 = urllib.request.Request(c, method="HEAD", headers={"User-Agent": "Installer/1.0"})
                with urllib.request.urlopen(req2, timeout=5) as r2:
                    if r2.status == 200:
                        tg_url = c
                        logger.info(f"Candidate Telegram archive OK: {c}")
                        break
            except Exception:
                continue

    if not tg_url:
        logger.error("Telegram archive link not found. Open https://telegram.org/dl/desktop/linux in a browser and paste a tar.xz URL into the script if needed.")
        raise RuntimeError("Telegram download link not found")

    tg_local = os.path.join(downloads_dir, os.path.basename(tg_url))
    download_with_retries(tg_url, tg_local, retries=3)
    # extract
    if os.path.exists("/opt/Telegram"):
        shutil.rmtree("/opt/Telegram")
    safe_makedirs("/opt/Telegram")
    run_cmd(["tar", "-xf", tg_local, "-C", "/opt/Telegram", "--strip-components=1"])
    tg_bin = "/opt/Telegram/Telegram"
    if os.path.exists(tg_bin):
        os.chmod(tg_bin, 0o755)
        try:
            subprocess.Popen([tg_bin], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            logger.debug("Could not launch Telegram binary; installation may still be ok.")
        logger.info("✅ Telegram installed.")
    else:
        raise FileNotFoundError("/opt/Telegram/Telegram not found after extraction")


def install_protonvpn(downloads_dir):
    logger.info("Installing ProtonVPN (repo package + app)")
    target = os.path.join(downloads_dir, os.path.basename(PROTONVPN_DEB_URL))
    download_with_retries(PROTONVPN_DEB_URL, target, retries=3)
    logger.info("Verifying ProtonVPN .deb SHA256...")
    actual = sha256_of_file(target)
    logger.info(f"Computed SHA256: {actual}")
    if actual != PROTONVPN_SHA256:
        logger.error("ProtonVPN .deb SHA256 mismatch. Aborting.")
        raise RuntimeError("ProtonVPN checksum mismatch")
    # Install repo package
    run_cmd(["dpkg", "-i", target])
    run_cmd(["apt", "update"])
    # Install package (note: package name variances exist; using protonvpn-gnome-desktop and proton-vpn-gnome-desktop both may be used on different repos)
    # Try the common package names in order
    tried = []
    for pkg in ("proton-vpn-gnome-desktop", "protonvpn-gnome-desktop", "proton-vpn"):
        try:
            run_cmd(["apt", "install", "-y", pkg])
            logger.info(f"Installed ProtonVPN package: {pkg}")
            break
        except Exception as e:
            logger.warning(f"Could not install ProtonVPN package '{pkg}': {e}")
            tried.append(pkg)
    # tray dependencies
    run_cmd(["apt", "install", "-y", "libayatana-appindicator3-1", "gir1.2-ayatanaappindicator3-0.1", "gnome-shell-extension-appindicator"])
    try:
        subprocess.Popen(["protonvpn-app"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        logger.info("✅ ProtonVPN installed and attempted to launch.")
    except Exception:
        logger.debug("ProtonVPN binary not found to launch right away; may require reboot or relogin.")


def install_rustscan(downloads_dir):
    logger.info("Installing RustScan (.deb)")
    target = os.path.join(downloads_dir, os.path.basename(RUSTSCAN_DEB_URL))
    download_with_retries(RUSTSCAN_DEB_URL, target, retries=3)
    run_cmd(["dpkg", "-i", target])
    run_cmd(["apt-get", "install", "-f", "-y"])
    try:
        resource.setrlimit(resource.RLIMIT_NOFILE, (5000, 5000))
    except Exception:
        logger.debug("Could not set RLIMIT_NOFILE; continuing.")
    logger.info("✅ RustScan installed.")


def install_vscode(downloads_dir):
    logger.info("Installing VS Code (.deb)")
    target = os.path.join(downloads_dir, "code.deb")
    download_with_retries(VSCODE_DEB_URL, target, retries=3)
    try:
        run_cmd(["dpkg", "-i", target])
    except Exception:
        run_cmd(["apt-get", "install", "-f", "-y"])
    try:
        subprocess.Popen(["code"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        logger.debug("Could not start VS Code now; it may require desktop session.")
    logger.info("✅ VS Code install attempted.")


def install_brave(downloads_dir):
    logger.info("Installing Brave (nightly) via installer script")
    installer_path = os.path.join(downloads_dir, "brave-install.sh")
    download_with_retries(BRAVE_INSTALLER_URL, installer_path, retries=3)
    os.chmod(installer_path, 0o755)
    env = os.environ.copy()
    env["CHANNEL"] = "nightly"
    run_cmd(f"sh {installer_path}", env=env)  # shell run
    # optional: pin to favorites
    desktop_file = ""
    for f in ("brave-browser.desktop", "brave-browser-nightly.desktop", "brave.desktop"):
        candidate = os.path.join("/usr/share/applications", f)
        if os.path.isfile(candidate):
            desktop_file = f
            break
    if desktop_file:
        _, favs_out, _ = run_cmd(["gsettings", "get", "org.gnome.shell", "favorite-apps"], capture_output=True)
        favs = favs_out.strip()
        if desktop_file not in favs:
            if favs.endswith("]"):
                new_favs = favs[:-1] + ", '" + desktop_file + "']"
            else:
                new_favs = favs + " ['" + desktop_file + "']"
            run_cmd(["gsettings", "set", "org.gnome.shell", "favorite-apps", new_favs])
    logger.info("✅ Brave installation attempted.")


def cleanup_downloads(downloads_dir):
    logger.info("Cleaning up downloads folder")
    try:
        for entry in os.listdir(downloads_dir):
            path = os.path.join(downloads_dir, entry)
            try:
                if os.path.isfile(path) or os.path.islink(path):
                    os.remove(path)
                elif os.path.isdir(path):
                    shutil.rmtree(path)
            except Exception as e:
                logger.warning(f"Could not remove {path}: {e}")
        logger.info("Cleanup complete.")
    except FileNotFoundError:
        logger.debug("Downloads folder not found for cleanup.")


# -------------------------
# Main
# -------------------------
def main():
    logger.info("=== Installer started ===")
    require_root()

    try:
        clone_repo(REPO_URL, REPO_DIRNAME)
        repo_path = os.path.abspath(REPO_DIRNAME)
        downloads_dir = setup_downloads(repo_path)

        backup_and_copy_grub(repo_path)
        backup_and_copy_wallpapers(repo_path)
        apply_gnome_tweaks()
        configure_dash_to_dock()

        install_telegram(downloads_dir)
        install_protonvpn(downloads_dir)
        install_rustscan(downloads_dir)
        install_vscode(downloads_dir)
        install_brave(downloads_dir)

        cleanup_downloads(downloads_dir)

        choice = input("Installation complete. Reboot now? (y/N) ").strip()
        if choice.lower().startswith("y"):
            logger.info("Rebooting now...")
            run_cmd(["reboot"])
        else:
            logger.info("Reboot skipped; logout/login may be required for some settings.")

        logger.info("=== Installer finished successfully ===")
    except Exception as e:
        logger.exception(f"Fatal error during installation: {e}")
        logger.error("Installation aborted due to errors. Check logs above.")
        sys.exit(1)


if __name__ == "__main__":
    main()
