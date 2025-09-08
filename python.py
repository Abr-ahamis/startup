#!/usr/bin/env python3
import os
import subprocess
import shutil
import sys
import time
from pathlib import Path

# ---------------------------
# Helper functions
# ---------------------------

def run(cmd, check=True, capture_output=False):
    """Run a command with pseudo-sudo privileges."""
    try:
        print(f"🟢 Running: {cmd}")
        return subprocess.run(cmd, shell=True, check=check, capture_output=capture_output, text=True)
    except subprocess.CalledProcessError as e:
        print(f"❌ Command failed: {cmd}\n{e}")
        if capture_output:
            return e
        return None

def ensure_dir(path):
    """Ensure a directory exists."""
    Path(path).mkdir(parents=True, exist_ok=True)

def backup_file(src, dest):
    """Backup a file if it exists."""
    if Path(src).exists():
        shutil.move(src, dest)
        print(f"🔹 Backed up {src} -> {dest}")

def copy_file(src, dest):
    """Copy file or directory."""
    if Path(src).is_dir():
        shutil.copytree(src, dest, dirs_exist_ok=True)
    else:
        shutil.copy2(src, dest)

# ---------------------------
# GRUB Themes
# ---------------------------

def setup_grub():
    ensure_dir("/boot/grub/themes/backup")
    ensure_dir("/usr/share/grub/themes/backup")

    if Path("/boot/grub/themes/kali").exists():
        backup_file("/boot/grub/themes/kali", "/boot/grub/themes/backup/kali.b")
    copy_file("kali", "/boot/grub/themes/")

    if Path("/usr/share/grub/themes/kali").exists():
        backup_file("/usr/share/grub/themes/kali", "/usr/share/grub/themes/backup/kali.b")
    copy_file("/boot/grub/themes/kali", "/usr/share/grub/themes/")

    backup_file("/boot/grub/grub.cfg", "/boot/grub/grub.cfg.b")
    copy_file("grub.cfg", "/boot/grub/")

    print("✅ GRUB setup completed.")

# ---------------------------
# Wallpapers
# ---------------------------

def setup_wallpapers():
    ensure_dir("/usr/share/backgrounds/kali/backup")
    wallpapers = [
        "kali-maze-16x9.jpg", "kali-tiles-16x9.jpg", "kali-oleo-16x9.png",
        "kali-tiles-purple-16x9.jpg", "kali-waves-16x9.png",
        "login.svg", "login-blurred"
    ]
    for wp in wallpapers:
        src_path = f"/usr/share/backgrounds/kali/{wp}"
        dest_path = f"/usr/share/backgrounds/kali/backup/{wp}.b"
        backup_file(src_path, dest_path)

    copy_file("20-wallpaper.svg", "/usr/share/backgrounds/kali/login.svg")
    copy_file("12-wallpaper.png", "/usr/share/backgrounds/kali/kali-maze-16x9.jpg")
    copy_file("1-wallpaper.png", "/usr/share/backgrounds/kali/kali-tiles-16x9.jpg")
    copy_file("2-wallpaper.png", "/usr/share/backgrounds/kali/kali-waves-16x9.png")
    copy_file("3-wallpaper.png", "/usr/share/backgrounds/kali/kali-oleo-16x9.png")
    copy_file("4-wallpaper.png", "/usr/share/backgrounds/kali/kali-tiles-purple-16x9.jpg")

    print("✅ Wallpapers setup completed.")

# ---------------------------
# GNOME Tweaks
# ---------------------------

def apply_gnome_tweaks():
    tweaks = {
        "org.gnome.desktop.interface font-name": "'DejaVu Serif Condensed 10'",
        "org.gnome.desktop.interface text-scaling-factor": "0.95",
        "org.gnome.desktop.background picture-options": "'zoom'"
    }
    for key, value in tweaks.items():
        run(f"gsettings set {key} {value}")
    print("✅ GNOME tweaks applied.")

# ---------------------------
# Dash-to-Dock
# ---------------------------

def configure_dash_to_dock():
    dock_settings = {
        "dock-position": "'LEFT'",
        "autohide": "true",
        "animation-time": "0.0",
        "hide-delay": "0.0",
        "pressure-threshold": "0.0",
        "dash-max-icon-size": "20"
    }
    for key, value in dock_settings.items():
        run(f"gsettings set org.gnome.shell.extensions.dash-to-dock {key} {value}")
    print("✅ Dash-to-Dock configured.")

# ---------------------------
# App installation helpers
# ---------------------------

def install_brave():
    run("curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly sh")
    desktop_files = ["brave-browser.desktop", "brave-browser-nightly.desktop", "brave.desktop"]
    desktop = next((f for f in desktop_files if Path(f"/usr/share/applications/{f}").exists()), None)
    if desktop:
        favs = run("gsettings get org.gnome.shell favorite-apps", capture_output=True).stdout.strip()
        if desktop not in favs:
            new_favs = favs[:-1] + f", '{desktop}']"
            run(f"gsettings set org.gnome.shell favorite-apps \"{new_favs}\"")
    print("✅ Brave installed and pinned.")
    run("nohup brave-browser &>/dev/null &")

def install_telegram():
    run("cd /tmp && wget -qO- https://telegram.org/dl/desktop/linux | grep -oP 'https://telegram.org/dl/desktop/linux/tsetup\\.\\d+\\.\\d+\\.\\d+\\.tar\\.xz' | head -n1 > /tmp/telegram_url.txt")
    url = Path("/tmp/telegram_url.txt").read_text().strip()
    run(f"wget -q {url} -O /tmp/tsetup_latest.tar.xz")
    run("sudo rm -rf /opt/Telegram && sudo mkdir -p /opt/Telegram")
    run("sudo tar -xf /tmp/tsetup_latest.tar.xz -C /opt/Telegram --strip-components=1")
    run("chmod +x /opt/Telegram/Telegram")
    run("nohup /opt/Telegram/Telegram &>/dev/null &")
    print("✅ Telegram installed.")

def install_protonvpn():
    run("wget https://repo.protonvpn.com/debian/dists/stable/main/binary-all/protonvpn-stable-release_1.0.8_all.deb -O /tmp/protonvpn-release.deb")
    run("sudo dpkg -i /tmp/protonvpn-release.deb")
    run("sudo apt update && sudo apt install -y protonvpn-gnome-desktop libayatana-appindicator3-1 gir1.2-ayatanaappindicator3-0.1 gnome-shell-extension-appindicator")
    run("nohup protonvpn-app &>/dev/null &")
    print("✅ ProtonVPN installed.")

def install_rustscan():
    run("wget https://github.com/RustScan/RustScan/releases/download/2.2.3/rustscan_2.2.3_amd64.deb -O /tmp/rustscan.deb")
    run("sudo dpkg -i /tmp/rustscan.deb")
    run("sudo apt-get install -f -y")
    run("ulimit -n 5000")
    print("✅ RustScan installed.")

def install_vscode():
    run("wget -q https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64 -O /tmp/code.deb")
    run("sudo dpkg -i /tmp/code.deb || sudo apt-get install -f -y")
    run("rm -f /tmp/code.deb")
    run("nohup code &>/dev/null &")
    print("✅ VS Code installed.")

# ---------------------------
# Main workflow
# ---------------------------

def main():
    # Ensure pseudo-privileges
    if os.geteuid() != 0:
        print("⚠️  Script needs sudo privileges, re-running with sudo...")
        os.execvp("sudo", ["sudo", sys.executable] + sys.argv)

    # Clone repo
    run("git clone https://github.com/Abr-ahamis/startup.git")
    os.chdir("startup")

    # Run all setup tasks
    setup_grub()
    setup_wallpapers()
    apply_gnome_tweaks()
    configure_dash_to_dock()
    install_brave()
    install_telegram()
    install_protonvpn()
    install_rustscan()
    install_vscode()

    # Prompt reboot
    choice = input("Installation complete. Reboot now? (y/N) ").strip().lower()
    if choice == "y":
        run("sudo reboot")
    else:
        print("✅ Setup complete. Reboot skipped.")

if __name__ == "__main__":
    main()
