#!/usr/bin/env python3
"""
install_startup.py — updated to use direct links and robust Telegram download logic,
verify ProtonVPN .deb checksum, and save installers inside the cloned repo's downloads folder.

Run as root:
sudo python3 install_startup.py
"""

import os
import sys
import subprocess
import shutil
import logging
import urllib.request
import re
import time
import hashlib
import resource

# -------------------------
# Configuration
# -------------------------
REPO_URL = "https://github.com/Abr-ahamis/startup.git"
REPO_DIRNAME = "startup"
DOWNLOADS_DIRNAME = "downloads"

# Direct links / pages provided
VSCODE_DEB_URL = "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
TELEGRAM_DL_PAGE = "https://telegram.org/dl/desktop/linux"  # this usually redirects to the tar.xz
BRAVE_INSTALLER_URL = "https://dl.brave.com/install.sh"
PROTONVPN_DEB_URL = "https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb"
# ProtonVPN SHA256 (as provided)
PROTONVPN_SHA256 = "0b14e71586b22e498eb20926c48c7b434b751149b1f2af9902ef1cfe6b03e180"

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

# -------------------------
# Logging setup
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
    """Run a command. cmd can be a list or string."""
    if isinstance(cmd, (list, tuple)):
        display = " ".join(cmd)
    else:
        display = str(cmd)
    logger.info(f"Running: {display}")
    try:
        result = subprocess.run(
            cmd,
            shell=isinstance(cmd, str),
            check=check,
            stdout=subprocess.PIPE if capture_output else None,
            stderr=subprocess.PIPE if capture_output else None,
            env=env,
        )
        if capture_output:
            out = result.stdout.decode(errors="ignore") if result.stdout else ""
            err = result.stderr.decode(errors="ignore") if result.stderr else ""
            logger.debug(f"stdout: {out}")
            logger.debug(f"stderr: {err}")
            return result, out, err
        return result
    except subprocess.CalledProcessError as e:
        logger.error(f"Command failed: {display}")
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
    logger.debug("Root check passed.")


def safe_makedirs(path, mode=0o755):
    os.makedirs(path, exist_ok=True)
    try:
        os.chmod(path, mode)
    except Exception:
        pass


def make_unique_path(path_base):
    """
    If path_base does not exist, return it.
    Otherwise append a timestamp (+counter) to make unique.
    """
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


# -------------------------
# Steps
# -------------------------
def clone_repo(repo_url, dest_dir):
    if os.path.isdir(dest_dir):
        logger.info(f"Repo directory '{dest_dir}' already exists. Attempting to pull latest.")
        try:
            run_cmd(["git", "-C", dest_dir, "pull"])
        except Exception:
            logger.warning("Git pull failed; renaming existing folder and cloning fresh.")
            backup_name = f"{dest_dir}.bak-{int(time.time())}"
            shutil.move(dest_dir, backup_name)
            run_cmd(["git", "clone", repo_url, dest_dir])
    else:
        run_cmd(["git", "clone", repo_url, dest_dir])


def setup_downloads(repo_path):
    downloads = os.path.join(repo_path, DOWNLOADS_DIRNAME)
    safe_makedirs(downloads)
    logger.info(f"Downloads folder prepared at: {downloads}")
    return downloads


def backup_and_copy_grub(repo_path):
    logger.info("Backing up and copying GRUB themes and grub.cfg")
    grub_cfg_path = "/boot/grub/grub.cfg"
    if os.path.exists(grub_cfg_path):
        dest = make_unique_path(grub_cfg_path + ".b")
        logger.info(f"Moving {grub_cfg_path} -> {dest}")
        shutil.move(grub_cfg_path, dest)
        logger.info(f"Backed up {grub_cfg_path} -> {dest}")

    src_grubcfg = os.path.join(repo_path, GRUB_CFG_SRC)
    if not os.path.exists(src_grubcfg):
        raise FileNotFoundError(f"Expected grub.cfg in repo at {src_grubcfg}")
    safe_makedirs("/boot/grub")
    shutil.copy(src_grubcfg, "/boot/grub/")
    logger.info(f"Copied {src_grubcfg} -> /boot/grub/")

    safe_makedirs("/boot/grub/themes/backup")
    safe_makedirs("/usr/share/grub/themes/backup")

    boot_kali = "/boot/grub/themes/kali"
    if os.path.isdir(boot_kali):
        desired = "/boot/grub/themes/backup/kali.b"
        dest = make_unique_path(desired)
        logger.info(f"Moving existing {boot_kali} -> {dest}")
        shutil.move(boot_kali, dest)
        logger.info(f"Moved existing {boot_kali} -> {dest}")

    repo_kali = os.path.join(repo_path, KALI_THEME_SRC)
    if not os.path.isdir(repo_kali):
        raise FileNotFoundError(f"Expected kali theme folder in repo at {repo_kali}")
    safe_makedirs("/boot/grub/themes")
    shutil.copytree(repo_kali, "/boot/grub/themes/kali", dirs_exist_ok=True)
    logger.info(f"Copied {repo_kali} -> /boot/grub/themes/")

    usr_kali = "/usr/share/grub/themes/kali"
    if os.path.isdir(usr_kali):
        desired = "/usr/share/grub/themes/backup/kali.b"
        dest = make_unique_path(desired)
        logger.info(f"Backing up {usr_kali} -> {dest}")
        shutil.move(usr_kali, dest)
        logger.info(f"Backed up {usr_kali} -> {dest}")

    safe_makedirs("/usr/share/grub/themes")
    shutil.copytree("/boot/grub/themes/kali", "/usr/share/grub/themes/kali", dirs_exist_ok=True)
    logger.info("Copied /boot/grub/themes/kali -> /usr/share/grub/themes/")


def backup_and_copy_wallpapers(repo_path):
    logger.info("Backing up and copying wallpapers")
    wallpaper_repo_path = os.path.join(repo_path, WALLPAPER_DIR)
    if not os.path.isdir(wallpaper_repo_path):
        raise FileNotFoundError(f"Expected wallpaper directory in repo at {wallpaper_repo_path}")

    target_dir = "/usr/share/backgrounds/kali"
    backup_dir = os.path.join(target_dir, "backup")
    safe_makedirs(backup_dir)

    for f in WALLPAPER_FILES_TO_BACKUP:
        target_file = os.path.join(target_dir, f)
        if os.path.exists(target_file):
            dest = make_unique_path(os.path.join(backup_dir, f + ".b"))
            logger.info(f"Backing up {target_file} -> {dest}")
            safe_makedirs(os.path.dirname(dest))
            shutil.move(target_file, dest)
            logger.info(f"Backed up {target_file} -> {dest}")

    for src_name, dest in WALLPAPER_FILES:
        src_file = os.path.join(wallpaper_repo_path, src_name)
        if not os.path.exists(src_file):
            raise FileNotFoundError(f"Expected wallpaper file {src_file} in repo")
        safe_makedirs(os.path.dirname(dest))
        shutil.copy(src_file, dest)
        logger.info(f"Copied {src_file} -> {dest}")


def apply_gnome_tweaks():
    logger.info("Applying GNOME Tweaks via gsettings")
    run_cmd(["gsettings", "set", "org.gnome.desktop.interface", "font-name", "Conifer 11"])
    run_cmd(["gsettings", "set", "org.gnome.desktop.interface", "text-scaling-factor", "0.95"])
    run_cmd(["gsettings", "set", "org.gnome.desktop.background", "picture-options", "zoom"])

    _, font_out, _ = run_cmd(["gsettings", "get", "org.gnome.desktop.interface", "font-name"], capture_output=True)
    _, scale_out, _ = run_cmd(["gsettings", "get", "org.gnome.desktop.interface", "text-scaling-factor"], capture_output=True)
    _, pic_out, _ = run_cmd(["gsettings", "get", "org.gnome.desktop.background", "picture-options"], capture_output=True)
    logger.info("✅ GNOME Tweaks settings applied:")
    logger.info(font_out.strip())
    logger.info(scale_out.strip())
    logger.info(pic_out.strip())


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

    keys = [
        "dock-position",
        "autohide",
        "animation-time",
        "hide-delay",
        "pressure-threshold",
        "dash-max-icon-size",
    ]
    for k in keys:
        _, out, _ = run_cmd(["gsettings", "get", "org.gnome.shell.extensions.dash-to-dock", k], capture_output=True)
        logger.info(f"{k}: {out.strip()}")


def install_telegram(downloads_dir):
    """
    Attempt 1: open TELEGRAM_DL_PAGE — often it redirects to the tar.xz directly (use resp.geturl()).
    Attempt 2: parse the page for a tsetup.*.tar.xz link.
    Save the tar.xz to downloads_dir and extract to /opt/Telegram
    """
    logger.info("Installing Telegram Desktop (following redirects or parsing page)")
    try:
        with urllib.request.urlopen(TELEGRAM_DL_PAGE, timeout=30) as resp:
            final_url = resp.geturl()
            page = resp.read().decode(errors="ignore")
    except Exception as e:
        logger.error("Failed to fetch Telegram download page or follow redirect")
        raise

    tg_url = None
    # If the request redirected directly to a tar.xz (common), use that final URL
    if final_url and final_url.endswith(".tar.xz"):
        tg_url = final_url
        logger.info(f"Detected redirect to Telegram archive: {tg_url}")
    else:
        # Fallback: search page HTML for tsetup.X.Y.Z.tar.xz links
        m = re.search(r"https://telegram\.org/dl/desktop/linux/tsetup\.\d+\.\d+\.\d+\.tar\.xz", page)
        if m:
            tg_url = m.group(0)
            logger.info(f"Found Telegram archive link on page: {tg_url}")

    if not tg_url:
        # As a last-resort attempt, try to find any .tar.xz link on the page
        m2 = re.search(r"https://[^\s'\"<>]+\.tar\.xz", page)
        if m2:
            tg_url = m2.group(0)
            logger.info(f"Fallback found .tar.xz link: {tg_url}")

    if not tg_url:
        logger.error("Could not locate a Telegram .tar.xz link by redirect or page parse.")
        raise RuntimeError("Telegram download link not found — try opening https://telegram.org/dl/desktop/linux to confirm availability")

    tg_local = os.path.join(downloads_dir, os.path.basename(tg_url))
    logger.info(f"Downloading Telegram archive to: {tg_local}")
    try:
        urllib.request.urlretrieve(tg_url, tg_local)
    except Exception as e:
        logger.error(f"Failed to download Telegram archive from {tg_url}: {e}")
        raise

    # install to /opt/Telegram
    if os.path.exists("/opt/Telegram"):
        shutil.rmtree("/opt/Telegram")
    safe_makedirs("/opt/Telegram")
    run_cmd(["tar", "-xf", tg_local, "-C", "/opt/Telegram", "--strip-components=1"])
    tg_bin = "/opt/Telegram/Telegram"
    if os.path.exists(tg_bin):
        os.chmod(tg_bin, 0o755)
        subprocess.Popen([tg_bin], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        logger.info("✅ Telegram installed and launched.")
    else:
        raise FileNotFoundError(f"Telegram binary not found after extraction at {tg_bin}")


def install_protonvpn(downloads_dir):
    """
    Download ProtonVPN release .deb into downloads_dir, verify checksum, dpkg -i, then apt install app.
    """
    logger.info("Installing ProtonVPN repository package (downloading .deb)")
    target = os.path.join(downloads_dir, os.path.basename(PROTONVPN_DEB_URL))
    logger.info(f"Downloading ProtonVPN repo package to {target}")
    urllib.request.urlretrieve(PROTONVPN_DEB_URL, target)

    # Verify SHA256
    logger.info("Verifying ProtonVPN package checksum...")
    actual = sha256_of_file(target)
    logger.info(f"Actual SHA256: {actual}")
    if actual != PROTONVPN_SHA256:
        logger.error("ProtonVPN checksum mismatch! Aborting installation.")
        raise RuntimeError("ProtonVPN .deb checksum does not match expected value")

    logger.info("Checksum OK — installing repository package")
    run_cmd(["dpkg", "-i", target])
    run_cmd(["apt", "update"])
    # Install the app and tray dependencies
    run_cmd(["apt", "install", "-y", "proton-vpn-gnome-desktop"])
    run_cmd(["apt", "install", "-y", "libayatana-appindicator3-1", "gir1.2-ayatanaappindicator3-0.1", "gnome-shell-extension-appindicator"])
    # Try to launch app
    try:
        subprocess.Popen(["protonvpn-app"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        logger.info("✅ ProtonVPN installed and (attempted) launched.")
    except FileNotFoundError:
        logger.warning("ProtonVPN app binary not found to launch; installation likely succeeded.")


def install_rustscan(downloads_dir):
    logger.info("Installing RustScan (.deb)")
    target = os.path.join(downloads_dir, os.path.basename(RUSTSCAN_DEB_URL))
    logger.info(f"Downloading RustScan .deb to {target}")
    urllib.request.urlretrieve(RUSTSCAN_DEB_URL, target)
    run_cmd(["dpkg", "-i", target])
    run_cmd(["apt-get", "install", "-f", "-y"])
    try:
        resource.setrlimit(resource.RLIMIT_NOFILE, (5000, 5000))
        logger.info("Set RLIMIT_NOFILE to 5000")
    except Exception:
        logger.warning("Could not set RLIMIT_NOFILE; continuing.")
    logger.info("✅ RustScan installed.")


def install_vscode(downloads_dir):
    logger.info("Installing VS Code (.deb) using provided direct link")
    target = os.path.join(downloads_dir, "code.deb")
    logger.info(f"Downloading VS Code to {target}")
    try:
        urllib.request.urlretrieve(VSCODE_DEB_URL, target)
    except Exception as e:
        logger.error(f"Failed to download VS Code: {e}")
        raise
    try:
        run_cmd(["dpkg", "-i", target])
    except subprocess.CalledProcessError:
        run_cmd(["apt-get", "install", "-f", "-y"])
    try:
        subprocess.Popen(["code"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        logger.info("✅ VS Code launched in background.")
    except FileNotFoundError:
        logger.warning("VS Code not found to launch; installation may still be successful.")


def install_brave(downloads_dir):
    """
    Save the Brave install script into downloads_dir and run it with CHANNEL=nightly,
    which matches: curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly sh
    """
    logger.info("Installing Brave (nightly)")
    installer_path = os.path.join(downloads_dir, "brave-install.sh")
    logger.info(f"Downloading Brave installer to {installer_path}")
    urllib.request.urlretrieve(BRAVE_INSTALLER_URL, installer_path)
    os.chmod(installer_path, 0o755)
    env = os.environ.copy()
    env["CHANNEL"] = "nightly"
    # Run the installer script (same effect as piping from curl)
    run_cmd(f"sh {installer_path}", env=env)
    # Pin Brave to favorites if .desktop exists
    desktop_file = ""
    for f in ("brave-browser.desktop", "brave-browser-nightly.desktop", "brave.desktop"):
        candidate = os.path.join("/usr/share/applications", f)
        if os.path.isfile(candidate):
            desktop_file = f
            break
    if desktop_file:
        favs_proc, favs_out, _ = run_cmd(["gsettings", "get", "org.gnome.shell", "favorite-apps"], capture_output=True)
        favs = favs_out.strip()
        if desktop_file not in favs:
            if favs.endswith("]"):
                new_favs = favs[:-1] + ", '" + desktop_file + "']"
            else:
                new_favs = favs + " ['" + desktop_file + "']"
            run_cmd(["gsettings", "set", "org.gnome.shell", "favorite-apps", new_favs])
    logger.info("✅ Brave installed and pinned (if .desktop was found).")


def cleanup_downloads(downloads_dir):
    logger.info("Cleaning up downloaded installer files in the repo downloads folder")
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
        logger.info("Downloads cleanup complete.")
    except FileNotFoundError:
        logger.warning("Downloads folder not found during cleanup; skipping.")


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

        # Core steps
        backup_and_copy_grub(repo_path)
        backup_and_copy_wallpapers(repo_path)
        apply_gnome_tweaks()
        configure_dash_to_dock()

        # Install applications (downloads go into repo/downloads/)
        install_telegram(downloads_dir)
        install_protonvpn(downloads_dir)
        install_rustscan(downloads_dir)
        install_vscode(downloads_dir)
        install_brave(downloads_dir)

        # Cleanup downloads (remove saved installers)
        cleanup_downloads(downloads_dir)

        # Reboot prompt
        choice = input("Installation complete. Reboot now? (y/N) ").strip()
        if choice.lower().startswith("y"):
            logger.info("Rebooting now...")
            run_cmd(["reboot"])
        else:
            logger.info("Reboot skipped. You may need to log out/in for some settings to take effect.")

        logger.info("=== Installer finished successfully ===")
    except Exception as e:
        logger.exception(f"Fatal error during installation: {e}")
        logger.error("Installation aborted due to errors. Check the log above for details.")
        sys.exit(1)


if __name__ == "__main__":
    main()
