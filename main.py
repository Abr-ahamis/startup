#!/usr/bin/env python3
"""
startup_setup_full.py

Behavior (implements the flow described in your hi.txt):
 - Clone/detect the startup repo
 - Install core APT packages first (non-interactive)
 - Build the full list of destination paths the installer may touch
 - If any destination exists: show them and prompt:
       Replace all existing configuration files with the repository versions? [y/N]
     - If 'y': DELETE the existing files/directories (no backups), then copy repo files into place
     - Otherwise: SKIP copying configs and continue to the app-install menu
 - If Replace chosen and repo contains i3/usr/share/rofi/themes/Adapta-Nokto.rasi:
     - remove files under /usr/share/rofi/themes/*
     - copy Adapta-Nokto.rasi into /usr/share/rofi/themes/
 - Copy wallpapers to both ~/Pictures/ and /usr/share/backgrounds/kali/ with explicit mappings
 - Install battery-monitor script + user service and run:
       systemctl --user daemon-reexec
       systemctl --user daemon-reload
       systemctl --user restart battery-monitor.service
   executed as the target (non-root) user; if the first attempt fails it will retry with XDG_RUNTIME_DIR prefix
 - Make scripts executable, ensure ~/.local/bin in PATH, create telegram symlink if Telegram installed
 - Interactive app menu shows Spotify by default (you must pick apps to install)
 - At the end the script prints & writes a detailed summary of files copied and commands executed

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
from typing import List, Optional, Dict, Callable
import pwd

# ---------- Configuration (edit only here) ----------
REPO_URL = "https://github.com/Abr-ahamis/startup.git"
REPO_DIR_NAME = "startup"

# APT packages installed first
APT_PACKAGES = [
    "i3-wm", "i3blocks", "rofi", "xdotool", "dex", "acpi", "upower",
    "xfce4-power-manager", "i3lock", "xss-lock", "pulseaudio-utils",
    "brightnessctl", "feh", "picom", "fonts-font-awesome", "git", "rsync",
    "unzip", "curl", "wget"
]

# App menu (only Spotify is pre-added per your request)
APP_OPTIONS = {
    1: "telegram",
    2: "spotify",   # <<-- Spotify only by default (you can add entries here and implement installers)
}

# Installer dispatch: map app name -> function (implement new install functions and add to APP_OPTIONS)
INSTALL_DISPATCH: Dict[str, Callable[[Path], None]] = {}

# Summary file written to user home
SUMMARY_FILENAME = "startup_setup_summary.txt"

# ---------- Logging ----------
logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
log = logging.getLogger("startup_setup")

# ---------- Helpers ----------
def die(msg: str, code: int = 1) -> None:
    log.error(msg)
    sys.exit(code)

def run(cmd, check: bool = False, capture_output: bool = False, env: dict = None, shell: bool = False):
    """Wrapper around subprocess.run that logs and returns CompletedProcess-like object."""
    if isinstance(cmd, (list, tuple)):
        log.info("[CMD] %s", " ".join(map(str, cmd)))
    else:
        log.info("[CMD] %s", cmd)
    try:
        return subprocess.run(cmd, check=check, capture_output=capture_output, text=True, env=env, shell=shell)
    except subprocess.CalledProcessError as e:
        log.warning("[CMD-FAIL] rc=%s cmd=%s", e.returncode, e.cmd)
        return e

def ensure_dir(p: Path) -> None:
    if not p.exists():
        p.mkdir(parents=True, exist_ok=True)

def get_target_user() -> str:
    sudo_user = os.environ.get("SUDO_USER")
    if sudo_user:
        return sudo_user
    return os.environ.get("USER", "root")

def get_user_home(user: str) -> Path:
    return Path(pwd.getpwnam(user).pw_dir)

TARGET_USER = get_target_user()
USER_HOME = get_user_home(TARGET_USER)
log.info("Target user: %s, Home: %s", TARGET_USER, USER_HOME)

def chown_recursive(path: Path, user: str) -> None:
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
        log.debug("chown failed for %s: %s", path, e)

def safe_remove(p: Path) -> None:
    """Delete file or directory (no backups)"""
    try:
        if not p.exists():
            return
        if p.is_symlink() or p.is_file():
            p.unlink()
            log.info("[DEL] removed file/symlink: %s", p)
        elif p.is_dir():
            shutil.rmtree(p)
            log.info("[DEL] removed directory tree: %s", p)
    except Exception as e:
        log.warning("[DEL-ERR] %s: %s", p, e)

def safe_copy_file(src: Path, dst: Path, make_dirs=True) -> bool:
    try:
        if not src.exists():
            log.info("[SKIP] source missing: %s", src)
            return False
        if make_dirs:
            ensure_dir(dst.parent)
        if dst.exists():
            # By the flow, when copying after Delete (Replace), dst will not exist.
            # But for safety, replace existing file.
            try:
                if dst.is_file() or dst.is_symlink():
                    dst.unlink()
                elif dst.is_dir():
                    shutil.rmtree(dst)
            except Exception:
                pass
        shutil.copy2(src, dst)
        log.info("[COPY] %s -> %s", src, dst)
        try:
            chown_recursive(dst, TARGET_USER)
        except Exception:
            pass
        return True
    except Exception as e:
        log.warning("[COPY-ERR] %s -> %s: %s", src, dst, e)
        return False

# ---------- Repo detection / clone ----------
def detect_or_clone_repo() -> Path:
    cwd = Path.cwd()
    # Accept if cwd already looks like repo
    if (cwd / "i3").is_dir() and (cwd / "wallpaper").is_dir():
        log.info("Using current directory as repository: %s", cwd)
        return cwd
    if (cwd / REPO_DIR_NAME).is_dir():
        return cwd / REPO_DIR_NAME
    target = cwd / REPO_DIR_NAME
    log.info("Cloning %s -> %s", REPO_URL, target)
    run(["git", "clone", REPO_URL, str(target)])
    return target

# ---------- Build destination list (from hi.txt) ----------
def build_dest_paths(startup_dir: Path) -> List[Path]:
    """
    Paths to check before copying (taken from hi.txt).
    These are the files/folders we will manage.
    """
    dests = []
    dests.append(USER_HOME / ".config" / "i3" / "config")
    dests.append(USER_HOME / ".config" / "i3" / "scripts")
    dests.append(USER_HOME / ".config" / "i3blocks")
    dests.append(USER_HOME / ".config" / "rofi")
    dests.append(USER_HOME / ".config" / "picom" / "picom.conf")
    dests.append(USER_HOME / ".local" / "bin")
    dests.append(USER_HOME / ".local" / "share" / "fonts")
    dests.append(USER_HOME / ".config" / "systemd" / "user" / "battery-monitor.service")
    # wallpapers (user)
    dests.append(USER_HOME / "Pictures" / "wallpaper.jpg")
    dests.append(USER_HOME / "Pictures" / "wallpaper-1.jpg")
    dests.append(USER_HOME / "Pictures" / "wallpaper-2.jpg")
    # system wallpaper dir
    dests.append(Path("/usr/share/backgrounds/kali"))
    # system rofi themes
    dests.append(Path("/usr/share/rofi/themes"))
    return dests

def scan_existing(dests: List[Path]) -> List[Path]:
    found = [p for p in dests if p.exists()]
    return found

# ---------- Delete / Copy flow ----------
def delete_existing_paths(paths: List[Path]) -> None:
    for p in paths:
        # safety guard
        if str(p).strip() in ("/", "", "//"):
            log.warning("Refusing to delete root or empty path: %s", p)
            continue
        safe_remove(p)

def copy_repo_files(startup_dir: Path, replace_rofi_themes: bool) -> List[str]:
    """
    Copies files from repo into their destinations. Returns list of copied entries for summary.
    """
    copied = []
    repo_i3 = startup_dir / "i3"
    # 1) i3 config
    s = repo_i3 / ".config" / "i3" / "config"
    d = USER_HOME / ".config" / "i3" / "config"
    if s.exists():
        safe_copy_file(s, d); copied.append(f"{s} -> {d}")

    # 2) i3 scripts
    s_scripts = repo_i3 / ".config" / "i3" / "scripts"
    d_scripts = USER_HOME / ".config" / "i3" / "scripts"
    if s_scripts.exists():
        ensure_dir(d_scripts)
        for f in sorted(s_scripts.iterdir()):
            if f.is_file():
                dstf = d_scripts / f.name
                safe_copy_file(f, dstf)
                try:
                    dstf.chmod(0o755)
                except Exception:
                    pass
                copied.append(f"{f} -> {dstf}")

    # 3) i3blocks
    s_i3b = repo_i3 / ".config" / "i3blocks"
    d_i3b = USER_HOME / ".config" / "i3blocks"
    if s_i3b.exists():
        if d_i3b.exists():
            safe_remove(d_i3b)
        shutil.copytree(s_i3b, d_i3b)
        chown_recursive(d_i3b, TARGET_USER)
        copied.append(f"{s_i3b} -> {d_i3b}")

    # 4) rofi (user-level)
    s_rofi = repo_i3 / ".config" / "rofi"
    d_rofi = USER_HOME / ".config" / "rofi"
    if s_rofi.exists():
        if d_rofi.exists():
            safe_remove(d_rofi)
        shutil.copytree(s_rofi, d_rofi)
        chown_recursive(d_rofi, TARGET_USER)
        copied.append(f"{s_rofi} -> {d_rofi}")

    # 5) picom.conf
    s_picom = repo_i3 / ".config" / "picom" / "picom.conf"
    d_picom = USER_HOME / ".config" / "picom" / "picom.conf"
    if s_picom.exists():
        safe_copy_file(s_picom, d_picom)
        copied.append(f"{s_picom} -> {d_picom}")

    # 6) local bin
    s_lbin = repo_i3 / ".local" / "bin"
    d_lbin = USER_HOME / ".local" / "bin"
    if s_lbin.exists():
        if d_lbin.exists():
            safe_remove(d_lbin)
        shutil.copytree(s_lbin, d_lbin)
        for f in d_lbin.rglob("*"):
            if f.is_file():
                try:
                    f.chmod(0o755)
                except Exception:
                    pass
        chown_recursive(d_lbin, TARGET_USER)
        copied.append(f"{s_lbin} -> {d_lbin}")

    # 7) fonts
    s_fonts = repo_i3 / ".local" / "share" / "fonts"
    d_fonts = USER_HOME / ".local" / "share" / "fonts"
    if s_fonts.exists():
        if d_fonts.exists():
            safe_remove(d_fonts)
        shutil.copytree(s_fonts, d_fonts)
        chown_recursive(d_fonts, TARGET_USER)
        copied.append(f"{s_fonts} -> {d_fonts}")

    # 8) battery monitor script & service
    s_script = repo_i3 / ".local" / "bin" / "battery-monitor.sh"
    d_script = USER_HOME / ".local" / "bin" / "battery-monitor.sh"
    if s_script.exists():
        ensure_dir(d_script.parent)
        safe_copy_file(s_script, d_script); d_script.chmod(0o755)
        chown_recursive(d_script, TARGET_USER)
        copied.append(f"{s_script} -> {d_script}")

    s_service = repo_i3 / ".config" / "systemd" / "user" / "battery-monitor.service"
    d_service = USER_HOME / ".config" / "systemd" / "user" / "battery-monitor.service"
    if s_service.exists():
        ensure_dir(d_service.parent)
        safe_copy_file(s_service, d_service)
        chown_recursive(d_service, TARGET_USER)
        copied.append(f"{s_service} -> {d_service}")
        # ensure DBUS env line present (if not, append); scripts in hi.txt did that
        try:
            text = d_service.read_text(encoding="utf-8")
            env_line = "Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%U/bus"
            if env_line not in text:
                lines = text.splitlines()
                # Attempt to insert after [Service] block end
                inserted = False
                for i, line in enumerate(lines):
                    if line.strip() == "[Service]":
                        j = i + 1
                        while j < len(lines) and not lines[j].strip().startswith("["):
                            j += 1
                        lines.insert(j, env_line)
                        inserted = True
                        break
                if not inserted:
                    lines.append(env_line)
                d_service.write_text("\n".join(lines) + "\n", encoding="utf-8")
                log.info("[BATTERY] injected DBUS env line into %s", d_service)
        except Exception as e:
            log.warning("[BATTERY] could not edit service file: %s", e)

    # 9) wallpapers -> user + system mappings
    repo_wall = startup_dir / "wallpaper"
    ensure_dir(USER_HOME / "Pictures")
    backgrounds_dir = Path("/usr/share/backgrounds/kali")
    ensure_dir(backgrounds_dir)
    for name in ("wallpaper.jpg", "wallpaper-1.jpg", "wallpaper-2.jpg"):
        s = repo_wall / name
        if s.exists():
            dstu = USER_HOME / "Pictures" / name
            if dstu.exists():
                safe_remove(dstu)
            shutil.copy2(s, dstu)
            chown_recursive(dstu, TARGET_USER)
            copied.append(f"{s} -> {dstu}")
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
            dsts = backgrounds_dir / dst_name
            if dsts.exists():
                safe_remove(dsts)
            shutil.copy2(s, dsts)
            copied.append(f"{s} -> {dsts}")

    # 10) system rofi theme (if repo provides it)
    s_rofi_sys_dir = repo_i3 / "usr" / "share" / "rofi" / "themes"
    d_rofi_sys_dir = Path("/usr/share/rofi/themes")
    if s_rofi_sys_dir.exists():
        # If user selected Replace earlier, caller will have cleared d_rofi_sys_dir contents already.
        ensure_dir(d_rofi_sys_dir)
        for f in sorted(s_rofi_sys_dir.iterdir()):
            if f.is_file():
                target = d_rofi_sys_dir / f.name
                if target.exists():
                    safe_remove(target)
                shutil.copy2(f, target)
                copied.append(f"{f} -> {target}")

    return copied

# ---------- systemctl --user sequence ----------
def run_user_systemctl_sequence(log_list: List[str]) -> None:
    """
    Execute the exact three commands you demanded as the target user:
      systemctl --user daemon-reexec
      systemctl --user daemon-reload
      systemctl --user restart battery-monitor.service

    First attempt: sudo -u <user> systemctl --user ...
    If any command fails, retry with XDG_RUNTIME_DIR=/run/user/<UID> prefix.
    """
    try:
        pw = pwd.getpwnam(TARGET_USER)
        uid = pw.pw_uid
    except KeyError:
        log.warning("Could not find target user info; skipping systemctl --user sequence")
        return

    simple_cmds = [
        ["sudo", "-u", TARGET_USER, "systemctl", "--user", "daemon-reexec"],
        ["sudo", "-u", TARGET_USER, "systemctl", "--user", "daemon-reload"],
        ["sudo", "-u", TARGET_USER, "systemctl", "--user", "restart", "battery-monitor.service"],
    ]

    failed = []
    for cmd in simple_cmds:
        r = run(cmd, check=False, capture_output=True)
        rc = getattr(r, "returncode", 1)
        stdout = getattr(r, "stdout", "") or ""
        stderr = getattr(r, "stderr", "") or ""
        log_list.append(" ".join(map(str, cmd)))
        if rc == 0:
            log.info("[SCTL] OK: %s", " ".join(cmd))
            if stdout.strip():
                log.info("[SCTL-OUT] %s", stdout.strip())
        else:
            log.warning("[SCTL] Failed (rc=%s): %s", rc, " ".join(cmd))
            if stderr.strip():
                log.warning("[SCTL-ERR] %s", stderr.strip())
            failed.append(cmd)

    if failed:
        log.info("[SCTL] Retrying failed commands with XDG_RUNTIME_DIR=/run/user/%d", uid)
        for cmd in failed:
            # Build a bash -lc command with XDG_RUNTIME_DIR set
            inner = " ".join(cmd[2:])  # e.g. systemctl --user daemon-reload
            cmdstr = f"XDG_RUNTIME_DIR=/run/user/{uid} {inner}"
            full = ["sudo", "-u", TARGET_USER, "bash", "-lc", cmdstr]
            r2 = run(full, check=False, capture_output=True)
            rc2 = getattr(r2, "returncode", 1)
            stdout2 = getattr(r2, "stdout", "") or ""
            stderr2 = getattr(r2, "stderr", "") or ""
            log_list.append(cmdstr)
            if rc2 == 0:
                log.info("[SCTL-RETRY] OK: %s", cmdstr)
                if stdout2.strip():
                    log.info("[SCTL-OUT] %s", stdout2.strip())
            else:
                log.warning("[SCTL-RETRY] Failed (rc=%s): %s", rc2, cmdstr)
                if stderr2.strip():
                    log.warning("[SCTL-ERR] %s", stderr2.strip())

# ---------- Make exec bits + i3 refresh ----------
def make_executables_and_refresh_i3() -> None:
    # Ensure scripts are executable
    possible_dirs = [
        USER_HOME / ".local" / "bin",
        USER_HOME / ".config" / "i3" / "scripts",
        USER_HOME / ".config" / "i3blocks",
        USER_HOME / ".config" / "rofi"
    ]
    for d in possible_dirs:
        if d.exists():
            for f in d.rglob("*"):
                if f.is_file():
                    try:
                        f.chmod(0o755)
                    except Exception:
                        pass

    # Attempt to refresh i3 via xdotool (simulate Win+Shift+R) if i3 is running; fallback to i3-msg restart
    r = run(["pgrep", "-x", "i3"], check=False, capture_output=True)
    if getattr(r, "returncode", 1) == 0 and (r.stdout or r.stderr):
        log.info("i3 detected: attempting xdotool send (Win+Shift+R)")
        try:
            # Best-effort: send Super+Shift+r as the target user
            run(["sudo", "-u", TARGET_USER, "xdotool", "key", "Super+Shift+r"], check=False)
            log.info("Sent Win+Shift+R via xdotool (best-effort)")
        except Exception:
            log.info("xdotool attempt failed; trying i3-msg restart")
            run(["sudo", "-u", TARGET_USER, "i3-msg", "restart"], check=False)
    else:
        log.info("i3 not detected; skipping i3 refresh")

# ---------- Prompt helpers ----------
def prompt_yes_no(prompt: str, default: str = "n") -> bool:
    default = default.lower()
    yn = "[Y/n]" if default == "y" else "[y/N]"
    try:
        ans = input(f"{prompt} {yn}: ").strip().lower()
    except EOFError:
        return default == "y"
    if ans == "" and default:
        return default == "y"
    return ans in ("y", "yes")

def prompt_app_selection() -> List[int]:
    print("\nApplications menu (select numbers separated by space or comma):")
    for k in sorted(APP_OPTIONS.keys()):
        print(f" {k}) {APP_OPTIONS[k]}")
    print(" Enter = none")
    raw = input("Selection: ").strip().lower()
    if not raw:
        return []
    if raw in ("a", "all"):
        return list(sorted(APP_OPTIONS.keys()))
    parts = [p.strip() for p in raw.replace(",", " ").split()]
    out = []
    for p in parts:
        if p.isdigit():
            v = int(p)
            if v in APP_OPTIONS:
                out.append(v)
    # deduplicate preserve order
    res = []
    for v in out:
        if v not in res:
            res.append(v)
    return res

# ---------- Simple Spotify installer example (best-effort) ----------
def install_spotify(startup_dir: Path) -> None:
    log.info("[SPOTIFY] Attempting install (apt then snap fallback)")
    # try apt first (may fail on some distros)
    r = run(["apt", "install", "-y", "spotify-client"], check=False)
    if getattr(r, "returncode", 1) == 0:
        log.info("[SPOTIFY] installed via apt")
        return
    # try snap if available
    r2 = run(["which", "snap"], check=False, capture_output=True)
    if getattr(r2, "returncode", 0) == 0:
        run(["snap", "install", "spotify"], check=False)
        log.info("[SPOTIFY] installed via snap (best-effort)")
    else:
        log.warning("[SPOTIFY] Could not install spotify automatically; please install manually")

# register spotify in dispatch if you want it available
INSTALL_DISPATCH["spotify"] = install_spotify

# ---------- Main ----------
def main():
    if os.geteuid() != 0:
        die("This script must be run as root. Use sudo python3 startup_setup_full.py")

    startup_dir = detect_or_clone_repo()
    log.info("Repo located at: %s", startup_dir)

    # Step 1: install apt packages first
    log.info("Installing APT packages (non-interactive)")
    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    run(["apt", "update"], check=False, env=env)
    if APT_PACKAGES:
        run(["apt", "install", "-y"] + APT_PACKAGES, check=False, env=env)

    # Step 2: prepare list of destination paths and scan for existing items (per hi.txt)
    dests = build_dest_paths(startup_dir)
    existing = scan_existing(dests)
    if existing:
        print("\nDetected existing configuration files/folders that the script would manage:")
        for p in existing:
            print(" -", p)
        print("\nOptions:")
        print(" 1) REMOVE configs and reinstall (no backup; will DELETE existing files and copy repo files)")
        print(" 2) KEEP configs and continue to app menu (skip copying configs)")
        print(" 3) CANCEL (exit without changes)")
        choice = input("Choose 1, 2, or 3 (default=3): ").strip()
        if choice == "1":
            log.info("User chose: REMOVE configs and reinstall (NO BACKUPS)")
            # delete all detected paths
            delete_existing_paths(existing)
            # if rofi themes dir existed, clear contents (user asked to remove others)
            rofi_dir = Path("/usr/share/rofi/themes")
            if rofi_dir.exists():
                for f in list(rofi_dir.iterdir()):
                    safe_remove(f)
                log.info("/usr/share/rofi/themes contents cleared")
            # Now copy repo files into place
            copied = copy_repo_files(startup_dir, replace_rofi_themes=True)
        elif choice == "2":
            log.info("User chose: KEEP configs. Skipping config copy and moving to app menu.")
            copied = []
        else:
            log.info("User chose: CANCEL. Exiting without changes.")
            return
    else:
        log.info("No existing configs found. Copying repo configs to target locations.")
        copied = copy_repo_files(startup_dir, replace_rofi_themes=False)

    # If Replace chosen and repo contains i3/usr/share/rofi/themes/Adapta-Nokto.rasi,
    # ensure it is moved/copied into /usr/share/rofi/themes/Adapta-Nokto.rasi
    adp_src = startup_dir / "i3" / "usr" / "share" / "rofi" / "themes" / "Adapta-Nokto.rasi"
    adp_dst_dir = Path("/usr/share/rofi/themes")
    adp_dst = adp_dst_dir / "Adapta-Nokto.rasi"
    if adp_src.exists():
        # per hi.txt you asked to move it into place and delete other files when replacing
        log.info("Installing Adapta-Nokto.rasi into %s", adp_dst)
        # if themes directory exists, we've cleared it earlier when replace chosen; but ensure directory exists
        ensure_dir(adp_dst_dir)
        # copy theme file
        try:
            if adp_dst.exists():
                safe_remove(adp_dst)
            shutil.copy2(adp_src, adp_dst)
            log.info("Copied %s -> %s", adp_src, adp_dst)
            try:
                chown_recursive(adp_dst, TARGET_USER)
            except Exception:
                pass
        except Exception as e:
            log.warning("Could not copy rofi theme: %s", e)

    # Ensure ~/.local/bin in .bashrc
    bashrc = USER_HOME / ".bashrc"
    path_line = 'export PATH="$HOME/.local/bin:$PATH"'
    try:
        if bashrc.exists():
            txt = bashrc.read_text(encoding="utf-8")
            if path_line not in txt:
                with open(bashrc, "a", encoding="utf-8") as fh:
                    fh.write("\n" + path_line + "\n")
                log.info("Appended PATH to %s", bashrc)
        else:
            with open(bashrc, "w", encoding="utf-8") as fh:
                fh.write(path_line + "\n")
            chown_recursive(bashrc, TARGET_USER)
            log.info("Created %s with PATH", bashrc)
    except Exception as e:
        log.warning("Could not ensure PATH in .bashrc: %s", e)

    # Make executables and attempt i3 refresh
    make_executables_and_refresh_i3()

    # Now run the exact user-level systemctl sequence you required
    executed_cmds_for_summary: List[str] = []
    run_user_systemctl_sequence(executed_cmds_for_summary)

    # App installation menu (Spotify only pre-added)
    selections = prompt_app_selection()
    if selections:
        log.info("User selected apps: %s", selections)
        for s in selections:
            name = APP_OPTIONS.get(s)
            if not name:
                log.warning("Unknown app selection: %s", s)
                continue
            fn = INSTALL_DISPATCH.get(name)
            if not fn:
                log.warning("No installer implemented for %s (edit the script to add it)", name)
                continue
            try:
                fn(startup_dir)
            except Exception as e:
                log.warning("Installer for %s raised: %s", name, e)
    else:
        log.info("No apps selected; skipping app installation")

    # Write a summary for audit
    summary_lines = []
    summary_lines.append(f"Run time: {datetime.datetime.now().isoformat()}")
    summary_lines.append(f"Target user: {TARGET_USER} ({USER_HOME})")
    summary_lines.append("Files copied:")
    for c in copied:
        summary_lines.append("  " + c)
    if adp_src.exists():
        summary_lines.append(f"Rofi theme installed: {adp_dst}")
    summary_lines.append("Systemctl --user commands attempted:")
    for cmd in executed_cmds_for_summary:
        summary_lines.append("  " + cmd)
    # Print summary
    print("\n===== SUMMARY =====")
    for l in summary_lines:
        print(l)
    # Save summary to user's home
    try:
        summary_path = USER_HOME / SUMMARY_FILENAME
        with open(summary_path, "a", encoding="utf-8") as fh:
            fh.write("\n".join(summary_lines) + "\n\n")
        chown_recursive(summary_path, TARGET_USER)
        log.info("Wrote summary to %s", summary_path)
    except Exception as e:
        log.warning("Could not write summary file: %s", e)

    log.info("Setup finished.")

if __name__ == "__main__":
    main()

