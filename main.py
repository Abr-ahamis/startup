#!/usr/bin/env python3
"""
startup_setup_full.py

- Clones/detects startup repo
- Installs apt packages
- Copies i3/rofi/picom/i3blocks/scripts/fonts/wallpapers with safe backups
- Ensures ~/.local/bin in PATH, sets executables, creates Telegram symlink
- Installs battery-monitor script/service and runs the exact systemctl --user sequence:
    systemctl --user daemon-reexec
    systemctl --user daemon-reload
    systemctl --user restart battery-monitor.service
  (attempted as the target user; retries with XDG_RUNTIME_DIR fallback)
- Moves repo rofi theme to /usr/share/rofi/themes with backup and optional removal
- Only Spotify is added to the app menu
- Clear EXAMPLE blocks show how to add apps/commands
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
import time
from pathlib import Path
from typing import List, Optional, Dict, Callable
import pwd

# ----------------------
# CONFIG - EDIT HERE
# ----------------------
REPO_URL = "https://github.com/Abr-ahamis/startup.git"
REPO_DIR_NAME = "startup"

APT_PACKAGES = [
    "i3-wm", "i3blocks", "rofi", "xdotool", "dex", "acpi", "upower",
    "xfce4-power-manager", "i3lock", "xss-lock", "pulseaudio-utils",
    "brightnessctl", "feh", "picom", "fonts-font-awesome", "git", "rsync",
    "unzip", "curl", "wget", "grub-customizer", "timeshift"
]

# App menu (only Spotify was added intentionally)
APP_OPTIONS = {
    1: "telegram",
    2: "brave-nightly",
    3: "vscode",
    4: "protonvpn",
    5: "virtualbox",
    6: "rustscan",
    7: "spotify",   # <-- Spotify only, per your request
}

# Where to write summary and system log (may require sudo to write system log)
SYSTEM_LOG = Path("/var/log/startup_setup_full.log")
USER_SUMMARY = "startup_setup_summary.txt"

# ----------------------
# Logging
# ----------------------
logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
log = logging.getLogger("startup_setup")

# ----------------------
# Utilities
# ----------------------
def die(msg: str, code: int = 1):
    log.error(msg)
    sys.exit(code)

def run(cmd, check: bool = False, capture_output: bool = False, env: Optional[dict] = None, shell: bool = False):
    if isinstance(cmd, (list, tuple)):
        log.info("[CMD] %s", " ".join(map(str, cmd)))
    else:
        log.info("[CMD] %s", cmd)
    try:
        return subprocess.run(cmd, check=check, capture_output=capture_output, text=True, env=env, shell=shell)
    except subprocess.CalledProcessError as e:
        log.warning("[CMD-FAIL] returncode=%s cmd=%s", e.returncode, e.cmd)
        if capture_output:
            log.warning("stdout: %s", e.stdout)
            log.warning("stderr: %s", e.stderr)
        if check:
            raise
        return e

def ensure_dir(p: Path, mode: int = 0o755):
    if not p.exists():
        log.info("[MKDIR] %s", p)
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
        log.info("[BACKUP] %s -> %s", dst, b)
        shutil.move(str(dst), str(b))
        return b
    except Exception as e:
        log.warning("[WARN] Could not backup %s: %s", dst, e)
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
        log.warning("[WARN] chown failed for %s: %s", path, e)

def safe_copy(src: Path, dst: Path, make_backup: bool = True, dirs_exist_ok: bool = False) -> bool:
    src = Path(src)
    dst = Path(dst)
    if not src.exists():
        log.info("[SKIP] Source missing: %s", src)
        return False
    ensure_dir(dst.parent)
    if dst.exists():
        if make_backup:
            backup_existing(dst)
        else:
            if dst.is_dir():
                shutil.rmtree(dst, ignore_errors=True)
            else:
                try:
                    dst.unlink()
                except Exception:
                    pass
    try:
        if src.is_dir():
            log.info("[COPY-DIR] %s -> %s", src, dst)
            shutil.copytree(src, dst, dirs_exist_ok=dirs_exist_ok)
        else:
            log.info("[COPY-FILE] %s -> %s", src, dst)
            shutil.copy2(src, dst)
        try:
            chown_recursive(dst, TARGET_USER)
        except Exception:
            pass
        return True
    except Exception as e:
        log.warning("[WARN] Copy failed %s -> %s : %s", src, dst, e)
        return False

# ----------------------
# Environment & user detection
# ----------------------
def get_target_user() -> str:
    sudo_user = os.environ.get("SUDO_USER")
    if sudo_user:
        return sudo_user
    return os.environ.get("USER", "root")

def get_user_home(user: str) -> Path:
    return Path(pwd.getpwnam(user).pw_dir)

TARGET_USER = get_target_user()
USER_HOME = get_user_home(TARGET_USER)
log.info("Target user: %s home: %s", TARGET_USER, USER_HOME)

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
    if (cwd / "i3").is_dir() and (cwd / "wallpaper").is_dir() and (cwd / "grub").is_dir():
        log.info("[REPO] Using current directory as repo")
        return cwd
    if (cwd / REPO_DIR_NAME).is_dir():
        return cwd / REPO_DIR_NAME
    target = cwd / REPO_DIR_NAME
    if target.exists():
        return target
    log.info("[REPO] Cloning %s -> %s", REPO_URL, target)
    r = run(["git", "clone", REPO_URL, str(target)], check=False, capture_output=True)
    if getattr(r, "returncode", 1) != 0:
        log.warning("[WARN] git clone returncode != 0")
    return target

# ----------------------
# APT packages
# ----------------------
def install_apt_packages(packages: List[str]):
    if not packages:
        return
    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    log.info("[APT] apt update")
    run(["apt", "update"], check=False, env=env)
    cmd = ["apt", "install", "-y"] + packages
    log.info("[APT] installing %d packages", len(packages))
    run(cmd, check=False, env=env)

# ----------------------
# COPY CORE CONFIGS (i3, rofi, picom, fonts, scripts, wallpapers, rofi theme)
# ----------------------
def copy_core_configs(startup_dir: Path):
    log.info("[COPY] Copying repo configs")
    repo_i3 = startup_dir / "i3"

    # i3 config
    safe_copy(repo_i3 / ".config" / "i3" / "config", USER_HOME / ".config" / "i3" / "config", make_backup=True)

    # i3 scripts
    src_i3_scripts = repo_i3 / ".config" / "i3" / "scripts"
    dst_i3_scripts = USER_HOME / ".config" / "i3" / "scripts"
    if src_i3_scripts.exists():
        ensure_dir(dst_i3_scripts)
        for f in sorted(src_i3_scripts.iterdir()):
            if f.is_file():
                safe_copy(f, dst_i3_scripts / f.name, make_backup=True)

    # i3blocks
    safe_copy(repo_i3 / ".config" / "i3blocks", USER_HOME / ".config" / "i3blocks", make_backup=True, dirs_exist_ok=True)

    # rofi
    safe_copy(repo_i3 / ".config" / "rofi", USER_HOME / ".config" / "rofi", make_backup=True, dirs_exist_ok=True)

    # picom
    safe_copy(repo_i3 / ".config" / "picom" / "picom.conf", USER_HOME / ".config" / "picom" / "picom.conf", make_backup=True)

    # local bin
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

    # ensure ~/.local/bin in .bashrc
    bashrc = USER_HOME / ".bashrc"
    path_line = 'export PATH="$HOME/.local/bin:$PATH"'
    if bashrc.exists():
        content = bashrc.read_text(encoding="utf-8")
        if path_line not in content:
            log.info("[PATH] Appending PATH to .bashrc")
            with open(bashrc, "a", encoding="utf-8") as fh:
                fh.write(f"\n{path_line}\n")
    else:
        log.info("[PATH] Creating .bashrc with PATH line")
        with open(bashrc, "w", encoding="utf-8") as fh:
            fh.write(f"{path_line}\n")

    # rofi system themes from repo -> /usr/share/rofi/themes (if present)
    src_rofi_sys = repo_i3 / "usr" / "share" / "rofi" / "themes"
    dst_rofi_sys = Path("/usr/share/rofi/themes")
    if src_rofi_sys.exists():
        # Ask user before destructive action (backup first)
        backup = unique_backup_name(dst_rofi_sys)
        if dst_rofi_sys.exists():
            log.info("[ROFI] Backing up %s -> %s", dst_rofi_sys, backup)
            try:
                shutil.copytree(dst_rofi_sys, backup)
            except Exception as e:
                log.warning("[ROFI] Backup failed: %s", e)
        else:
            ensure_dir(dst_rofi_sys)

        # Copy the repo theme file(s)
        for f in sorted(src_rofi_sys.iterdir()):
            try:
                safe_copy(f, dst_rofi_sys / f.name, make_backup=True)
            except Exception as e:
                log.warning("[ROFI] Could not copy %s: %s", f, e)

        # If the repo provided Adapta-Nokto.rasi and user agrees, remove other themes
        adapta = src_rofi_sys / "Adapta-Nokto.rasi"
        if adapta.exists():
            print("\n[IMPORTANT] Found Adapta-Nokto.rasi in repo.")
            ans = input("Do you want to (1) keep existing system rofi themes, (2) replace system themes with Adapta-Nokto (backup first) ? [1/2] (default=1): ").strip()
            if ans == "2":
                # After backup, remove others and ensure only Adapta stays
                try:
                    for p in dst_rofi_sys.iterdir():
                        if p.name != "Adapta-Nokto.rasi":
                            if p.is_file():
                                p.unlink()
                            else:
                                shutil.rmtree(p, ignore_errors=True)
                    log.info("[ROFI] Replaced system rofi themes, kept Adapta-Nokto.rasi")
                except Exception as e:
                    log.warning("[ROFI] Could not prune themes: %s", e)

    # wallpapers
    repo_wall = startup_dir / "wallpaper"
    ensure_dir(USER_HOME / "Pictures")
    backgrounds_dir = Path("/usr/share/backgrounds/kali")
    ensure_dir(backgrounds_dir)
    for name in ("wallpaper.jpg", "wallpaper-1.jpg", "wallpaper-2.jpg"):
        s = repo_wall / name
        if s.exists():
            safe_copy(s, USER_HOME / "Pictures" / name, make_backup=True)
    # special mappings
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
                log.info("[WALL] Mapped %s -> %s", s, backgrounds_dir / dst_name)
            except Exception as e:
                log.warning("[WALL] Could not copy %s -> %s : %s", s, dst_name, e)

# ----------------------
# Battery monitor install + systemctl --user sequence
# ----------------------
def install_battery_monitor(startup_dir: Path):
    repo_script = startup_dir / "i3" / ".local" / "bin" / "battery-monitor.sh"
    repo_service = startup_dir / "i3" / ".config" / "systemd" / "user" / "battery-monitor.service"
    dst_script = USER_HOME / ".local" / "bin" / "battery-monitor.sh"
    dst_service = USER_HOME / ".config" / "systemd" / "user" / "battery-monitor.service"

    if repo_script.exists():
        ensure_dir(dst_script.parent)
        if safe_copy(repo_script, dst_script, make_backup=True):
            try:
                dst_script.chmod(0o755)
            except Exception:
                pass
            try:
                chown_recursive(dst_script, TARGET_USER)
            except Exception:
                pass
            log.info("[BATTERY] Installed script %s", dst_script)

    if repo_service.exists():
        ensure_dir(dst_service.parent)
        if safe_copy(repo_service, dst_service, make_backup=True):
            try:
                # Ensure DBUS env line exists inside [Service]
                env_line = "Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%U/bus"
                text = dst_service.read_text(encoding="utf-8")
                if env_line not in text:
                    lines = text.splitlines()
                    inserted = False
                    for i, ln in enumerate(lines):
                        if ln.strip() == "[Service]":
                            j = i + 1
                            while j < len(lines) and not lines[j].strip().startswith("["):
                                j += 1
                            lines.insert(j, env_line)
                            inserted = True
                            break
                    if not inserted:
                        lines.append("")
                        lines.append(env_line)
                    dst_service.write_text("\n".join(lines) + "\n", encoding="utf-8")
                    try:
                        chown_recursive(dst_service, TARGET_USER)
                    except Exception:
                        pass
                    log.info("[BATTERY] Ensured DBUS env in service file")
            except Exception as e:
                log.warning("[BATTERY] Could not edit service file: %s", e)

    # Now run the EXACT user-level systemctl sequence you requested.
    try:
        pw = pwd.getpwnam(TARGET_USER)
        uid = pw.pw_uid
        cmds = [
            ["sudo", "-u", TARGET_USER, "systemctl", "--user", "daemon-reexec"],
            ["sudo", "-u", TARGET_USER, "systemctl", "--user", "daemon-reload"],
            ["sudo", "-u", TARGET_USER, "systemctl", "--user", "restart", "battery-monitor.service"],
        ]
        log.info("[BATTERY] Running systemctl --user sequence as %s (first attempt without XDG prefix)", TARGET_USER)
        failed = []
        for c in cmds:
            r = run(c, check=False, capture_output=True)
            rc = getattr(r, "returncode", 1)
            if rc != 0:
                failed.append((c, r))
            else:
                log.info("[BATTERY] Command OK: %s", " ".join(c))

        if failed:
            log.warning("[BATTERY] Some commands failed, retrying with XDG_RUNTIME_DIR prefix.")
            xdg_prefix = f"XDG_RUNTIME_DIR=/run/user/{uid}"
            for c in cmds:
                s = " ".join(c[3:]) if len(c) > 3 else " ".join(c[2:])
                cmd_str = f"{xdg_prefix} sudo -u {TARGET_USER} bash -lc 'systemctl --user {' '.join(c[3:]) if len(c)>3 else c[2]}'"
                # Safer: run each full command individually using bash -lc and XDG prefix
                # Construct the direct commands:
                if len(c) == 4:
                    svc_cmd = f"{xdg_prefix} sudo -u {TARGET_USER} bash -lc 'systemctl --user {c[2]} {c[3]}'"
                elif len(c) == 3:
                    svc_cmd = f"{xdg_prefix} sudo -u {TARGET_USER} bash -lc 'systemctl --user {c[2]}'"
                else:
                    svc_cmd = f"{xdg_prefix} sudo -u {TARGET_USER} bash -lc 'systemctl --user {' '.join(c[2:])}'"
                r2 = run(svc_cmd, check=False, capture_output=True, shell=True)
                if getattr(r2, "returncode", 1) == 0:
                    log.info("[BATTERY] Retry OK: %s", svc_cmd)
                else:
                    log.warning("[BATTERY] Retry failed: %s", svc_cmd)
    except Exception as e:
        log.warning("[BATTERY] Could not run systemctl sequence: %s", e)

# ----------------------
# Make executables & i3 refresh
# ----------------------
def set_executables_and_restart_i3():
    # make scripts executable in common places
    for d in [USER_HOME / ".config" / "i3blocks" / "scripts",
              USER_HOME / ".config" / "rofi",
              USER_HOME / ".config" / "i3" / "scripts",
              USER_HOME / ".local" / "bin"]:
        if d.exists():
            for f in d.rglob("*"):
                if f.is_file():
                    try:
                        f.chmod(0o755)
                    except Exception:
                        pass

    # Attempt Win+Shift+R via xdotool (multiple DISPLAY/XAUTHORITY combos)
    def try_send_xdotool_refresh():
        displays = [":0", ":0.0", ":1"]
        xauth_candidates = [
            USER_HOME / ".Xauthority",
            Path(f"/run/user/{pwd.getpwnam(TARGET_USER).pw_uid}/gdm/Xauthority")
        ]
        for disp in displays:
            for xauth in xauth_candidates:
                env = os.environ.copy()
                env["DISPLAY"] = disp
                if xauth.exists():
                    env["XAUTHORITY"] = str(xauth)
                # send key
                cmd = ["sudo", "-u", TARGET_USER, "xdotool", "key", "Super+Shift+r"]
                r = run(cmd, check=False, capture_output=True, env=env)
                if getattr(r, "returncode", 1) == 0:
                    log.info("[I3-REFRESH] Sent xdotool refresh with DISPLAY=%s XAUTHORITY=%s", disp, xauth)
                    return True
        return False

    refreshed = False
    try:
        # only try if i3 appears to be running
        r = run(["pgrep", "-x", "i3"], check=False, capture_output=True)
        if getattr(r, "returncode", 0) == 0 and r.stdout.strip():
            log.info("[I3-REFRESH] i3 detected, attempting xdotool refresh")
            refreshed = try_send_xdotool_refresh()
            if not refreshed:
                log.info("[I3-REFRESH] xdotool failed, trying i3-msg restart as user")
                run(["sudo", "-u", TARGET_USER, "i3-msg", "restart"], check=False)
        else:
            log.info("[I3-REFRESH] i3 not detected, skipping refresh")
    except Exception as e:
        log.warning("[I3-REFRESH] Exception during refresh: %s", e)

# ----------------------
# App installers (examples) - only Spotify is auto-included
# ----------------------
def install_telegram(startup_dir: Optional[Path] = None):
    log.info("[TELEGRAM] Installing Telegram (best-effort)")
    tfile = Path("/tmp/tsetup.tar.xz")
    run(["wget", "-q", "https://telegram.org/dl/desktop/linux", "-O", str(tfile)], check=False)
    opt = Path("/opt/Telegram")
    if opt.exists():
        backup_existing(opt)
    ensure_dir(opt)
    run(["tar", "-xf", str(tfile), "-C", str(opt), "--strip-components=1"], check=False)
    tbin = opt / "Telegram"
    if tbin.exists():
        try:
            tbin.chmod(0o755)
        except Exception:
            pass
        try:
            link = Path("/usr/local/bin/telegram")
            if link.exists() or link.is_symlink():
                try:
                    link.unlink()
                except Exception:
                    pass
            link.symlink_to(tbin)
            log.info("[TELEGRAM] Created symlink %s -> %s", link, tbin)
        except Exception as e:
            log.warning("[TELEGRAM] Could not create symlink: %s", e)

def install_spotify(startup_dir: Optional[Path] = None):
    log.info("[SPOTIFY] Installing Spotify (best-effort apt then snap fallback)")
    # Simple apt repository attempt (may require apt-key or signed repo for specific distros)
    try:
        # Try apt install directly first (some distros have spotify in repos)
        r = run(["apt", "install", "-y", "spotify-client"], check=False)
        if getattr(r, "returncode", 1) == 0:
            log.info("[SPOTIFY] Installed via apt")
            return
    except Exception:
        pass
    # Fallback to snap if installed
    r = run(["which", "snap"], check=False, capture_output=True)
    if getattr(r, "returncode", 1) == 0 and r.stdout.strip():
        run(["snap", "install", "spotify"], check=False)
        log.info("[SPOTIFY] Installed via snap")
    else:
        log.warning("[SPOTIFY] Could not install spotify; add repository manually or install snap")

# Dispatch map; to add app: implement installer and map name -> function here
INSTALL_DISPATCH: Dict[str, Callable[[Optional[Path]], None]] = {
    "telegram": install_telegram,
    "spotify": install_spotify,
    # EXAMPLE:
    # "my-app": install_my_app,
}

# ----------------------
# Interactive prompts
# ----------------------
def prompt_yes_no(prompt: str, default: str = "y") -> bool:
    default = default.lower()
    yn = "[Y/n]" if default == "y" else "[y/N]"
    while True:
        try:
            choice = input(f"{prompt} {yn}: ").strip().lower()
        except EOFError:
            return default == "y"
        if choice == "" and default:
            return default == "y"
        if choice in ("y", "yes"):
            return True
        if choice in ("n", "no"):
            return False
        print("Please answer 'y' or 'n'.")

def prompt_multi_select() -> List[int]:
    print("Select applications to install (numbers separated by spaces or commas), 'a' for all, Enter for none:")
    for k in sorted(APP_OPTIONS.keys()):
        print(f" {k}) {APP_OPTIONS[k]}")
    raw = input("Enter selection (e.g. '1 3 5' or 'a'): ").strip().lower()
    if not raw:
        return []
    if raw in ("a", "all"):
        return list(sorted(APP_OPTIONS.keys()))
    parts = [p.strip() for p in raw.replace(",", " ").split()]
    out = []
    for p in parts:
        if p.isdigit():
            i = int(p)
            if i in APP_OPTIONS:
                out.append(i)
        else:
            # allow typed names
            for k, name in APP_OPTIONS.items():
                if p == name.lower() or p == name.split()[0].lower():
                    out.append(k)
    return list(dict.fromkeys(out))  # preserve order, remove duplicates

# ----------------------
# Main flow
# ----------------------
def main():
    require_root()
    startup_dir = detect_or_clone_repo()

    # 1) Install apt packages (best-effort)
    install_apt_packages(APT_PACKAGES)

    # 2) Copy configs
    copy_core_configs(startup_dir)

    # 3) Install battery monitor and run systemctl --user sequence
    install_battery_monitor(startup_dir)

    # 4) Set executables + i3 refresh
    set_executables_and_restart_i3()

    # 5) App install prompt
    selections = prompt_multi_select()
    if not selections:
        log.info("[APPS] No apps selected")
    else:
        for sel in selections:
            name = APP_OPTIONS.get(sel)
            if not name:
                log.warning("[APPS] Unknown selection %s", sel)
                continue
            fn = INSTALL_DISPATCH.get(name)
            if not fn:
                log.warning("[APPS] No installer for %s (implement it in INSTALL_DISPATCH)", name)
                continue
            try:
                log.info("[APPS] Installing %s", name)
                fn(startup_dir)
            except Exception as e:
                log.warning("[APPS] Installer for %s raised: %s", name, e)

    # 6) Summary write (basic)
    try:
        summary_path = USER_HOME / USER_SUMMARY
        with open(summary_path, "a", encoding="utf-8") as fh:
            fh.write(f"\n--- run at {datetime.datetime.now().isoformat()} ---\n")
            fh.write(f"Target user: {TARGET_USER}\n")
            fh.write(f"Repo: {startup_dir}\n")
        log.info("[DONE] Setup complete; summary written to %s", summary_path)
    except Exception as e:
        log.warning("[DONE] Could not write summary: %s", e)

if __name__ == "__main__":
    main()
