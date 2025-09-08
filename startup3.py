#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys
import time
import logging

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s"
)

# ---------------------------
# Helper functions
# ---------------------------

def run(cmd, check=True):
    """Run a shell command."""
    logging.info(f"Running: {cmd}")
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if check and result.returncode != 0:
        logging.error(f"Command failed: {cmd}\n{result.stderr}")
        raise RuntimeError(f"Command failed: {cmd}")
    return result.stdout.strip()


def ensure_dir(path):
    os.makedirs(path, exist_ok=True)


# ---------------------------
# Clone or update repo
# ---------------------------
repo_url = "https://github.com/Abr-ahamis/startup.git"
repo_path = os.path.join(os.getcwd(), "startup")
downloads_dir = os.path.join(repo_path, "downloads")
ensure_dir(downloads_dir)

if not os.path.exists(repo_path):
    run(f"git clone {repo_url}")
else:
    logging.info("Repo directory 'startup' already exists. Attempting to pull latest.")
    run(f"git -C {repo_path} pull")


# ---------------------------
# Backup and copy GRUB themes
# ---------------------------
def backup_and_copy_grub(repo_path):
    logging.info("Backing up and copying GRUB themes and grub.cfg")

    timestamp = int(time.time())
    # grub.cfg
    grub_cfg_src = os.path.join(repo_path, "grub.cfg")
    grub_cfg_dst = "/boot/grub/grub.cfg"
    if os.path.exists(grub_cfg_dst):
        backup_path = f"{grub_cfg_dst}.b.{timestamp}"
        shutil.move(grub_cfg_dst, backup_path)
        logging.info(f"Moved {grub_cfg_dst} -> {backup_path}")
    shutil.copy(grub_cfg_src, grub_cfg_dst)
    logging.info(f"Copied {grub_cfg_src} -> {grub_cfg_dst}")

    # Themes
    for theme_dir in ["/boot/grub/themes", "/usr/share/grub/themes"]:
        ensure_dir(os.path.join(theme_dir, "backup"))
        src_kali = os.path.join(repo_path, "kali") if theme_dir == "/boot/grub/themes" else "/boot/grub/themes/kali"
        dst_kali = os.path.join(theme_dir, "kali")
        if os.path.exists(dst_kali):
            backup_kali = os.path.join(theme_dir, f"backup/kali.b.{timestamp}")
            shutil.move(dst_kali, backup_kali)
            logging.info(f"Moved existing {dst_kali} -> {backup_kali}")
        shutil.copytree(src_kali, dst_kali)
        logging.info(f"Copied {src_kali} -> {dst_kali}")


backup_and_copy_grub(repo_path)


# ---------------------------
# Backup and copy wallpapers
# ---------------------------
def backup_and_copy_wallpapers(repo_path):
    logging.info("Backing up and copying wallpapers")

    wallpaper_dir = os.path.join(repo_path, "wallpaper")
    target_dir = "/usr/share/backgrounds/kali"
    backup_dir = os.path.join(target_dir, "backup")
    ensure_dir(backup_dir)

    wallpaper_map = {
        "kali-maze-16x9.jpg": "12-wallpaper.png",
        "kali-tiles-16x9.jpg": "1-wallpaper.png",
        "kali-waves-16x9.png": "2-wallpaper.png",
        "kali-oleo-16x9.png": "3-wallpaper.png",
        "kali-tiles-purple-16x9.jpg": "4-wallpaper.png",
        "login.svg": "20-wallpaper.svg",
        "login-blurred": "2-wallpaper.png",  # updated
    }

    timestamp = int(time.time())
    for orig_file, new_file in wallpaper_map.items():
        orig_path = os.path.join(target_dir, orig_file)
        backup_path = os.path.join(backup_dir, f"{orig_file}.b.{timestamp}")

        if os.path.exists(orig_path):
            shutil.move(orig_path, backup_path)
            logging.info(f"Backed up {orig_path} -> {backup_path}")

        src_path = os.path.join(wallpaper_dir, new_file)
        if os.path.exists(src_path):
            shutil.copy(src_path, orig_path)
            logging.info(f"Copied {src_path} -> {orig_path}")
        else:
            logging.warning(f"Source wallpaper {src_path} not found")


backup_and_copy_wallpapers(repo_path)


# ---------------------------
# Apply GNOME Tweaks
# ---------------------------
def apply_gnome_tweaks():
    logging.info("Applying GNOME Tweaks via gsettings")
    tweaks = [
        "gsettings set org.gnome.desktop.interface font-name 'DejaVu Serif Condensed 10'",
        "gsettings set org.gnome.desktop.interface text-scaling-factor 0.95",
        "gsettings set org.gnome.desktop.background picture-options 'zoom'"
    ]
    for cmd in tweaks:
        run(cmd)
    logging.info("✅ GNOME Tweaks applied")


apply_gnome_tweaks()


# ---------------------------
# Configure Dash-to-Dock
# ---------------------------
def configure_dash_to_dock():
    logging.info("Configuring Dash-to-Dock")
    dash_cmds = [
        "gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'LEFT'",
        "gsettings set org.gnome.shell.extensions.dash-to-dock autohide true",
        "gsettings set org.gnome.shell.extensions.dash-to-dock animation-time 0.0",
        "gsettings set org.gnome.shell.extensions.dash-to-dock hide-delay 0.0",
        "gsettings set org.gnome.shell.extensions.dash-to-dock pressure-threshold 0.0",
        "gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 20"
    ]
    for cmd in dash_cmds:
        run(cmd)
    logging.info("✅ Dash-to-Dock configured")


configure_dash_to_dock()


# ---------------------------
# Download helper
# ---------------------------
def download_file(url, dest):
    run(f"wget -q {url} -O {dest}")


# ---------------------------
# Install Telegram
# ---------------------------
def install_telegram(download_dir):
    logging.info("Installing Telegram Desktop")
    url = "https://telegram.org/dl/desktop/linux/tsetup.6.1.3.tar.xz"  # fixed direct link
    dest = os.path.join(download_dir, "tsetup_latest.tar.xz")
    download_file(url, dest)

    tgt_dir = "/opt/Telegram"
    if os.path.exists(tgt_dir):
        shutil.rmtree(tgt_dir)
    ensure_dir(tgt_dir)
    run(f"sudo tar -xf {dest} -C {tgt_dir} --strip-components=1")
    run(f"chmod +x {tgt_dir}/Telegram")
    run(f"nohup {tgt_dir}/Telegram &>/dev/null &")
    logging.info("✅ Telegram installed")


install_telegram(downloads_dir)


# ---------------------------
# Install ProtonVPN
# ---------------------------
def install_protonvpn(download_dir):
    logging.info("Installing ProtonVPN")
    url = "https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb"
    deb_path = os.path.join(download_dir, "protonvpn-release.deb")
    download_file(url, deb_path)

    run(f"sudo dpkg -i {deb_path} && sudo apt update")
    run("sudo apt install -y protonvpn-gnome-desktop libayatana-appindicator3-1 gir1.2-ayatanaappindicator3-0.1 gnome-shell-extension-appindicator")
    run("nohup protonvpn-app &>/dev/null &")
    logging.info("✅ ProtonVPN installed")


install_protonvpn(downloads_dir)


# ---------------------------
# Install RustScan
# ---------------------------
def install_rustscan(download_dir):
    logging.info("Installing RustScan")
    url = "https://github.com/RustScan/RustScan/releases/download/2.2.3/rustscan_2.2.3_amd64.deb"
    deb_path = os.path.join(download_dir, "rustscan.deb")
    download_file(url, deb_path)
    run(f"sudo dpkg -i {deb_path} || sudo apt-get install -f -y")
    run("ulimit -n 5000")
    logging.info("✅ RustScan installed")


install_rustscan(downloads_dir)


# ---------------------------
# Install VS Code
# ---------------------------
def install_vscode(download_dir):
    logging.info("Installing VS Code")
    url = "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
    deb_path = os.path.join(download_dir, "code.deb")
    download_file(url, deb_path)
    run(f"sudo dpkg -i {deb_path} || sudo apt-get install -f -y")
    os.remove(deb_path)
    run("nohup code &>/dev/null &")
    logging.info("✅ VS Code installed")


install_vscode(downloads_dir)


# ---------------------------
# Install Brave Nightly
# ---------------------------
def install_brave():
    logging.info("Installing Brave (Nightly)")
    run("curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly sh")

    # Detect Brave .desktop
    desktop = None
    for f in ["brave-browser.desktop", "brave-browser-nightly.desktop", "brave.desktop"]:
        if os.path.exists(f"/usr/share/applications/{f}"):
            desktop = f
            break

    if desktop:
        favs = run("gsettings get org.gnome.shell favorite-apps")
        if desktop not in favs:
            new = favs.rstrip("]") + f", '{desktop}']"
            run(f"gsettings set org.gnome.shell favorite-apps \"{new}\"")
        logging.info("✅ Brave installed and pinned")
    else:
        logging.warning("Could not find Brave .desktop file")


install_brave()


# ---------------------------
# Cleanup downloads
# ---------------------------
shutil.rmtree(downloads_dir, ignore_errors=True)
logging.info("✅ Download folder cleaned up")


# ---------------------------
# Prompt before reboot
# ---------------------------
choice = input("Installation complete. Reboot now? (y/N) ").strip().lower()
if choice == "y":
    run("sudo reboot")
else:
    logging.info("Reboot skipped. You may need to log out/in for some settings to take effect.")
