#!/usr/bin/env python3
from __future__ import annotations

import sys

# Prevent creation of `__pycache__/` and `.pyc` files when this script runs.
sys.dont_write_bytecode = True

import os
import pwd
import re
import shutil
import subprocess
import termios
import tempfile
import time
import tty
import json
import select
import curses
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

# =========================
# Constants
# =========================
REPO_URL = "https://github.com/Abr-ahamis/startup.git"
REPO_DIR_NAME = "startup"

APT_PACKAGES = [
    "i3",
    "i3-wm",
    "i3blocks",
    "rofi",
    "xdotool",
    "dex",
    "acpi",
    "upower",
    "xfce4-power-manager",
    "i3lock",
    "xss-lock",
    "flameshot",
    "pulseaudio-utils",
    "brightnessctl",
    "feh",
    "picom",
    "fonts-font-awesome",
    "git",
    "rsync",
    "unzip",
    "ruby-notify",
    "curl",
    "wget",
    "grub-customizer",
    "timeshift",
    "redshift",
    "bmon",
    "nload",
    "iftop",
]

PKG_CMD_MAP: Dict[str, str] = {
    "i3": "i3",
    "i3-wm": "i3",
    "i3blocks": "i3blocks",
    "rofi": "rofi",
    "picom": "picom",
    "feh": "feh",
    "redshift": "redshift",
    "curl": "curl",
    "wget": "wget",
    "git": "git",
    "rsync": "rsync",
    "unzip": "unzip",
    "xdotool": "xdotool",
}

SYSTEM_WALLPAPER_TARGETS = [
    "kali-cubes-16x9.jpg",
    "kali-cubes2-16x9.jpg",
    "kali-cubes-purple-16x9.jpg",
    "kali-glitch-16x9.jpg",
    "kali-hack-16x9.jpg",
    "kali-maze-16x9.jpg",
    "kali-net-16x9.jpg",
    "kali-oleo-16x9.png",
    "kali-tiles-16x9.jpg",
    "kali-tiles-purple-16x9.jpg",
    "kali-waves-16x9.png",
    "login-blurred",
    "login.svg",
]


# =========================
# UI helpers
# =========================
CSI = "\033["
RESET = CSI + "0m"
BOLD = CSI + "1m"
GREEN = CSI + "32m"
YELLOW = CSI + "33m"
RED = CSI + "31m"
CYAN = CSI + "36m"


def _c(s: str, col: str) -> str:
    return f"{col}{s}{RESET}"


def ok(s: str) -> str:
    return _c(s, GREEN)


def warn(s: str) -> str:
    return _c(s, YELLOW)


def err(s: str) -> str:
    return _c(s, RED)


def info(s: str) -> str:
    return _c(s, CYAN)


def section(title: str) -> None:
    print("──────────────────────────────────────────────")
    print(title)
    print("──────────────────────────────────────────────")


def header(target_user: str, startup_dir: Path) -> None:
    print()
    print("╔" + "═" * 50 + "╗")
    print("║" + "{:^50}".format("Walcome back Sr.") + "║")
    print("╚" + "═" * 50 + "╝")
    print(f"👤 Target User  : {target_user}")
    print(f"⚙️  Envrmin      : {startup_dir}")
    print("🚀 Starting setup...\n")


# =========================
# Runtime context
# =========================
TARGET_USER = os.environ.get("SUDO_USER") or os.environ.get("USER", "root")
try:
    _pw = pwd.getpwnam(TARGET_USER)
    USER_HOME = Path(_pw.pw_dir)
    TARGET_UID = _pw.pw_uid
    TARGET_GID = _pw.pw_gid
except Exception:
    USER_HOME = Path(os.environ.get("HOME", "/root"))
    TARGET_UID = os.getuid()
    TARGET_GID = os.getgid()

BACKUP_ROOT = USER_HOME / ".BACKUPDV"
BACKUP_SESSION_DIR = BACKUP_ROOT / datetime.now().strftime("%Y%m%d-%H%M%S")
BACKUP_INDEX_PATH = BACKUP_SESSION_DIR / ".index.json"
LOG_PATH = USER_HOME / ".startup_install.log"
STATE_PATH = USER_HOME / ".startup_state.json"

DRY_RUN = False
STATE: Dict[str, List[str] | bool] = {
    "new_apt_packages": [],
    "optional_installed": [],
    "copied_targets": [],
    "created_targets": [],
}


# =========================
# Core utilities
# =========================
def run(
    cmd: Sequence[str] | str,
    *,
    check: bool = False,
    capture_output: bool = True,
    shell: bool = False,
    env: Optional[dict] = None,
) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        check=check,
        capture_output=capture_output,
        text=True,
        shell=shell,
        env=env,
    )


def log_line(msg: str) -> None:
    try:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with LOG_PATH.open("a", encoding="utf-8") as f:
            f.write(f"[{datetime.now().isoformat()}] {msg}\n")
        try:
            os.chown(LOG_PATH, TARGET_UID, TARGET_GID)
        except Exception:
            pass
    except Exception:
        pass


def load_state() -> None:
    global STATE
    if not STATE_PATH.exists():
        return
    try:
        data = json.loads(STATE_PATH.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            for k in ("new_apt_packages", "optional_installed", "copied_targets", "created_targets"):
                v = data.get(k, [])
                if isinstance(v, list):
                    STATE[k] = [str(x) for x in v]
    except Exception as ex:
        log_line(f"failed to load state: {ex}")


def save_state() -> None:
    try:
        STATE_PATH.write_text(json.dumps(STATE, indent=2), encoding="utf-8")
        try:
            os.chown(STATE_PATH, TARGET_UID, TARGET_GID)
        except Exception:
            pass
    except Exception as ex:
        log_line(f"failed to save state: {ex}")


def _state_add(key: str, value: str) -> None:
    arr = STATE.setdefault(key, [])
    if isinstance(arr, list) and value not in arr:
        arr.append(value)


def ensure_dir(path: Path) -> None:
    if DRY_RUN:
        return
    path.mkdir(parents=True, exist_ok=True)


def _is_within(path: Path, root: Path) -> bool:
    try:
        path.absolute().relative_to(root.absolute())
        return True
    except Exception:
        return False


def _chown_user(path: Path) -> None:
    if DRY_RUN:
        return
    try:
        os.lchown(path, TARGET_UID, TARGET_GID)
    except Exception:
        pass


def _chown_tree(root: Path) -> None:
    if DRY_RUN:
        return
    try:
        os.lchown(root, TARGET_UID, TARGET_GID)
    except Exception:
        pass
    if not root.is_dir() or root.is_symlink():
        return
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        for name in dirnames:
            try:
                os.lchown(Path(dirpath) / name, TARGET_UID, TARGET_GID)
            except Exception:
                pass
        for name in filenames:
            try:
                os.lchown(Path(dirpath) / name, TARGET_UID, TARGET_GID)
            except Exception:
                pass


def _fix_user_ownership(path: Path) -> None:
    if not _is_within(path, USER_HOME):
        return
    _chown_tree(path)


def ensure_dir_owned(path: Path) -> None:
    ensure_dir(path)
    if not _is_within(path, USER_HOME):
        return
    cur = path
    while True:
        _chown_user(cur)
        if cur == USER_HOME:
            break
        cur = cur.parent


def cleanup_python_bytecode(startup_dir: Path) -> None:
    if DRY_RUN:
        return
    try:
        for pyc in startup_dir.rglob("*.pyc"):
            try:
                pyc.unlink()
            except Exception:
                pass
        for d in startup_dir.rglob("__pycache__"):
            try:
                if d.is_dir():
                    shutil.rmtree(d)
            except Exception:
                pass
    except Exception as ex:
        log_line(f"bytecode cleanup failed in {startup_dir}: {ex}")


def require_root() -> None:
    if os.geteuid() == 0:
        return
    print(err("Run with sudo/root. Example: sudo python3 setup.py"))
    sys.exit(1)


def ask_yes_no(prompt: str, default: bool = True) -> bool:
    suffix = "[Y/n]" if default else "[y/N]"
    while True:
        try:
            ans = input(f"{prompt} {suffix}: ").strip().lower()
        except EOFError:
            return default
        if not ans:
            return default
        if ans in ("y", "yes"):
            return True
        if ans in ("n", "no"):
            return False
        print(warn("Please answer y or n."))


def read_key() -> str:
    if not sys.stdin.isatty():
        return ""
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        first = os.read(fd, 1)
        if not first:
            return ""
        if first != b"\x1b":
            return first.decode(errors="ignore")
        # Read typical arrow/function sequence tails if available.
        tail = b""
        for _ in range(4):
            r, _, _ = select.select([fd], [], [], 0.02)
            if not r:
                break
            part = os.read(fd, 1)
            if not part:
                break
            tail += part
            if part.isalpha() or part == b"~":
                break
        ch = first + tail
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
    return ch.decode(errors="ignore")


def _menu_rewind(lines: int) -> None:
    if lines <= 0:
        return
    # Move cursor up and clear to end of screen for in-place redraw.
    print(f"\033[{lines}F\033[J", end="")


def _fit_line(s: str) -> str:
    """Trim lines to terminal width so redraw line counting stays accurate."""
    width = shutil.get_terminal_size((120, 24)).columns
    if width < 10:
        return s
    if len(s) <= width - 1:
        return s
    return s[: max(0, width - 4)] + "..."


def backup_destination(dst: Path) -> Path:
    rel = backup_relative(dst)
    return BACKUP_SESSION_DIR / rel


def backup_relative(dst: Path) -> Path:
    abs_dst = dst.absolute()
    if _is_within(abs_dst, USER_HOME):
        return abs_dst.relative_to(USER_HOME.absolute())
    return Path(abs_dst.as_posix().lstrip("/"))


def _unique_backup_path(path: Path) -> Path:
    if not path.exists() and not path.is_symlink():
        return path
    for i in range(1, 10_000):
        cand = path.with_name(f"{path.name}.dup{i}")
        if not cand.exists() and not cand.is_symlink():
            return cand
    # Extremely unlikely; last-resort uniqueness.
    return path.with_name(f"{path.name}.dup{int(time.time())}")


def _write_backup_index(items: Sequence[str]) -> None:
    if DRY_RUN:
        return
    try:
        ensure_dir_owned(BACKUP_SESSION_DIR)
        BACKUP_INDEX_PATH.write_text(json.dumps(sorted(set(items)), indent=2), encoding="utf-8")
        try:
            os.chown(BACKUP_INDEX_PATH, TARGET_UID, TARGET_GID)
        except Exception:
            pass
    except Exception as ex:
        log_line(f"failed to write backup index: {ex}")


_BACKUP_INDEX: set[str] = set()


def backup_existing(dst: Path, *, move: bool = True) -> Optional[Path]:
    if not dst.exists() and not dst.is_symlink():
        return None
    rel = backup_relative(dst)
    _BACKUP_INDEX.add(rel.as_posix())

    ensure_dir_owned(BACKUP_SESSION_DIR)
    target = _unique_backup_path(backup_destination(dst))
    ensure_dir_owned(target.parent)
    if DRY_RUN:
        mode = "move" if move else "copy"
        print(info(f"[dry-run] backup({mode}) {dst} -> {target}"))
        _write_backup_index(list(_BACKUP_INDEX))
        return target
    try:
        if move:
            shutil.move(str(dst), str(target))
        else:
            if dst.is_symlink():
                link_target = os.readlink(dst)
                target.symlink_to(link_target)
            elif dst.is_dir():
                shutil.copytree(dst, target, symlinks=True)
            else:
                shutil.copy2(dst, target)
        _write_backup_index(list(_BACKUP_INDEX))
        return target
    except Exception as ex:
        log_line(f"backup failed for {dst}: {ex}")
        return None


def safe_copy(src: Path, dst: Path, dirs_exist_ok: bool = False) -> bool:
    if not src.exists() and not src.is_symlink():
        log_line(f"missing source: {src}")
        return False
    if not ensure_dir_safe(dst.parent):
        return False
    existed_before = dst.exists() or dst.is_symlink()
    if existed_before:
        if backup_existing(dst, move=True) is None:
            log_line(f"refusing to overwrite {dst}; backup failed")
            return False
    try:
        if DRY_RUN:
            print(info(f"[dry-run] copy {src} -> {dst}"))
            return True
        if src.is_symlink():
            dst.symlink_to(os.readlink(src))
        elif src.is_dir():
            # Intentionally replace the destination directory on conflict (backed up above).
            # This avoids copytree failing to overwrite existing symlinks.
            shutil.copytree(src, dst, symlinks=True)
        else:
            tmp = dst.with_name(dst.name + ".tmp")
            shutil.copy2(src, tmp)
            os.replace(tmp, dst)
        _state_add("copied_targets", str(dst))
        if not existed_before:
            _state_add("created_targets", str(dst))
        _fix_user_ownership(dst)
        return True
    except Exception as ex:
        log_line(f"copy failed {src} -> {dst}: {ex}")
        return False


def ensure_dir_safe(path: Path) -> bool:
    if path.exists() or path.is_symlink():
        if path.is_dir() and not path.is_symlink():
            return True
        if backup_existing(path, move=True) is None:
            log_line(f"refusing to replace {path}; backup failed")
            return False
    try:
        ensure_dir_owned(path)
        return True
    except Exception as ex:
        log_line(f"ensure_dir failed {path}: {ex}")
        return False


def safe_move(src: Path, dst: Path) -> bool:
    if not src.exists() and not src.is_symlink():
        log_line(f"missing source: {src}")
        return False
    if not ensure_dir_safe(dst.parent):
        return False
    if dst.exists() or dst.is_symlink():
        if backup_existing(dst, move=True) is None:
            log_line(f"refusing to overwrite {dst}; backup failed")
            return False
    try:
        if DRY_RUN:
            print(info(f"[dry-run] move {src} -> {dst}"))
            return True
        shutil.move(str(src), str(dst))
        _fix_user_ownership(dst)
        return True
    except Exception as ex:
        log_line(f"move failed {src} -> {dst}: {ex}")
        return False


def detect_or_clone_repo() -> Path:
    cwd = Path.cwd()
    if (cwd / "i3").is_dir() and (cwd / "grub").is_dir() and (cwd / "wallpaper").is_dir():
        return cwd
    if (cwd / REPO_DIR_NAME / "i3").is_dir():
        return cwd / REPO_DIR_NAME

    target = cwd / REPO_DIR_NAME
    if DRY_RUN:
        return target
    if shutil.which("git") is None:
        return target
    cp = run(["git", "clone", "--depth", "1", REPO_URL, str(target)])
    if cp.returncode != 0:
        log_line(f"git clone failed: {cp.stderr or cp.stdout}")
    return target


# =========================
# Package installation
# =========================
def is_pkg_installed(pkg: str) -> bool:
    if DRY_RUN:
        return False
    cmd = PKG_CMD_MAP.get(pkg)
    if cmd and shutil.which(cmd):
        return True
    cp = run(["dpkg-query", "-W", "-f=${Status}", pkg], capture_output=True)
    return cp.returncode == 0 and cp.stdout.strip() == "install ok installed"


def wait_for_apt_lock(timeout_s: int = 60) -> bool:
    if DRY_RUN:
        return True
    for _ in range(timeout_s):
        lock_busy = run(["fuser", "/var/lib/dpkg/lock-frontend"], capture_output=True)
        apt_busy = run(["pgrep", "-x", "apt"], capture_output=True)
        dpkg_busy = run(["pgrep", "-x", "dpkg"], capture_output=True)
        if lock_busy.returncode != 0 and apt_busy.returncode != 0 and dpkg_busy.returncode != 0:
            return True
        time.sleep(1)
    return False


def apt_install(packages: List[str], show_output: bool = True) -> bool:
    if not packages:
        return True
    if DRY_RUN:
        print(info(f"[dry-run] apt-get update && apt-get install {' '.join(packages)}"))
        return True
    if not wait_for_apt_lock(60):
        log_line("apt lock wait timed out")
        return False

    env = os.environ.copy()
    env["DEBIAN_FRONTEND"] = "noninteractive"
    env["APT_LISTCHANGES_FRONTEND"] = "none"

    def pre_install_repair() -> None:
        # User request: always run this before install attempts.
        run(["dpkg", "--configure", "-a"], capture_output=True)

    # Always quiet apt output and show only percentage progress.
    total_steps = 1 + len(packages)  # update + each package
    done = 0

    def pct() -> int:
        return int((done / total_steps) * 100) if total_steps else 100

    pre_install_repair()
    print(info(f"[{pct():>3}%] apt update"))
    cp_up = run(["apt-get", "update", "-y"], env=env, capture_output=True)
    done += 1
    if cp_up.returncode != 0:
        log_line(f"apt update failed: {cp_up.stderr or cp_up.stdout or 'unknown error'}")
        return False

    ok_all = True
    for pkg in packages:
        pre_install_repair()
        print(info(f"[{pct():>3}%] installing {pkg}"))
        cp = run(["apt-get", "install", "-y", pkg], env=env, capture_output=True)
        if cp.returncode != 0:
            log_line(f"apt install failed for {pkg}: {cp.stderr or cp.stdout or 'unknown error'}")
            run(["apt-get", "-f", "install", "-y"], env=env, capture_output=True)
            run(["dpkg", "--configure", "-a"], env=env, capture_output=True)
            pre_install_repair()
            cp_retry = run(["apt-get", "install", "-y", pkg], env=env, capture_output=True)
            if cp_retry.returncode != 0:
                ok_all = False
                log_line(f"apt retry failed for {pkg}: {cp_retry.stderr or cp_retry.stdout or 'unknown error'}")
        done += 1

    print(info(f"[{pct():>3}%] package install stage finished"))
    return ok_all


def install_packages() -> None:
    section("📦 PACKAGE INSTALLATION SECTION")
    missing: List[str] = []
    for pkg in APT_PACKAGES:
        if is_pkg_installed(pkg):
            print(ok(f"[✔] {pkg:<20} already installed"))
        else:
            missing.append(pkg)
    if missing:
        section("📦 Missing packages")
        for pkg in missing:
            print(warn(f"[?] {pkg:<20} Missing packages"))

    if missing:
        print(info("➜ Installing missing packages..."))
        apt_install(missing, show_output=True)

    section("📦 PACKAGE INSTALLATION SECTION")
    still_missing = [pkg for pkg in APT_PACKAGES if not is_pkg_installed(pkg)]
    if still_missing and not DRY_RUN:
        # Silent second retry ("background") before final summary.
        apt_install(still_missing, show_output=False)
        still_missing = [pkg for pkg in APT_PACKAGES if not is_pkg_installed(pkg)]

    if not still_missing:
        print(ok("ALL installed"))
    else:
        print(warn(f"ALL installed exapte: {', '.join(still_missing)}"))
        log_line(f"packages still missing after retries: {', '.join(still_missing)}")
    installed_now = [pkg for pkg in missing if is_pkg_installed(pkg)]
    for pkg in installed_now:
        _state_add("new_apt_packages", pkg)
    save_state()


# =========================
# Config deployment
# =========================
def copy_configs(startup_dir: Path) -> None:
    section("📁 CONFIG DEPLOYMENT SECTION")
    repo_i3 = startup_dir / "i3"

    s1 = safe_copy(repo_i3 / ".config" / "i3" / "config", USER_HOME / ".config" / "i3" / "config")
    s2 = safe_copy(repo_i3 / ".config" / "i3blocks", USER_HOME / ".config" / "i3blocks", dirs_exist_ok=True)
    s3 = safe_copy(repo_i3 / ".config" / "rofi", USER_HOME / ".config" / "rofi", dirs_exist_ok=True)
    s4 = safe_copy(repo_i3 / ".config" / "picom" / "picom.conf", USER_HOME / ".config" / "picom" / "picom.conf")

    # Some repo variants have a different rofi launcher layout. If a launcher symlink is present
    # but dangling, try to repoint it to the new location so the copied config remains usable.
    if s3 and not DRY_RUN:
        rofi_root = USER_HOME / ".config" / "rofi"
        scripts_dir = rofi_root / "scripts"
        launcher_link = scripts_dir / "launcher"
        if scripts_dir.exists() and launcher_link.is_symlink() and not launcher_link.exists():
            candidates = [
                Path("../launchers/type-1/launcher.sh"),
                Path("../launchers/launcher.sh"),
            ]
            for rel in candidates:
                if (scripts_dir / rel).exists():
                    try:
                        if backup_existing(launcher_link) is None:
                            log_line(f"refusing to modify {launcher_link}; backup failed")
                            break
                        launcher_link.symlink_to(rel)
                        _fix_user_ownership(launcher_link)
                    except Exception as ex:
                        log_line(f"failed to repair rofi launcher symlink {launcher_link}: {ex}")
                    break

    safe_copy(
        repo_i3 / ".config" / "i3" / "scripts" / "terminal-font.sh",
        USER_HOME / ".config" / "i3" / "scripts" / "terminal-font.sh",
    )

    src_bin = repo_i3 / ".local" / "bin"
    dst_bin = USER_HOME / ".local" / "bin"
    ensure_dir_owned(dst_bin)
    if src_bin.exists():
        for item in sorted(src_bin.iterdir()):
            safe_copy(item, dst_bin / item.name)

    src_fonts = repo_i3 / ".local" / "share" / "fonts"
    dst_fonts = USER_HOME / ".local" / "share" / "fonts"
    ensure_dir_owned(dst_fonts)
    font_count = 0
    if src_fonts.exists():
        for item in sorted(src_fonts.iterdir()):
            if safe_copy(item, dst_fonts / item.name):
                font_count += 1

    print(ok("[✔] i3 config updated") if s1 else warn("[✖] i3 config update failed"))
    print(ok("[✔] i3blocks config updated") if s2 else warn("[✖] i3blocks config update failed"))
    print(ok("[✔] rofi theme applied") if s3 else warn("[✖] rofi theme update failed"))
    print(ok("[✔] picom configuration updated") if s4 else warn("[✖] picom config update failed"))
    print(ok(f"[✔] Fonts installed ({font_count})"))


def copy_wallpapers(startup_dir: Path) -> None:
    section("🖼 WALLPAPER SECTION")
    repo_wall = startup_dir / "wallpaper"
    sources = [repo_wall / "wallpaper.jpg", repo_wall / "wallpaper-1.jpg", repo_wall / "wallpaper-2.jpg"]
    sources = [p for p in sources if p.exists()]
    if not sources:
        print(warn("No wallpaper source images found."))
        return

    pics = USER_HOME / "Pictures"
    ensure_dir_owned(pics)
    for src in sources:
        safe_copy(src, pics / src.name)

    kali_dir = Path("/usr/share/backgrounds/kali")
    ensure_dir(kali_dir)
    replaced = 0
    cycle_i = 0
    for target_name in SYSTEM_WALLPAPER_TARGETS:
        dst = kali_dir / target_name
        src = sources[cycle_i % len(sources)]
        cycle_i += 1
        if safe_copy(src, dst):
            replaced += 1

    src_i3 = repo_wall / "wallpaper-1.jpg"
    i3_wall = kali_dir / "wallpaper-1.jpg"
    if src_i3.exists():
        safe_copy(src_i3, i3_wall)
    print(ok(f"[✔] Wallpapers replaced ({replaced})"))
    print(ok("wallpaper are replaced"))
    print(ok("i3 wallpaper set"))


# =========================
# Battery monitor
# =========================
def run_user_systemctl(args: str) -> Tuple[bool, str]:
    try:
        uid = pwd.getpwnam(TARGET_USER).pw_uid
    except Exception as ex:
        return False, str(ex)

    runtime_dir = f"/run/user/{uid}"
    command = f"XDG_RUNTIME_DIR={runtime_dir} systemctl --user {args}"
    if DRY_RUN:
        print(info(f"[dry-run] sudo -u {TARGET_USER} bash -lc '{command}'"))
        return True, "dry-run"

    if not Path(runtime_dir).exists():
        run(["loginctl", "enable-linger", TARGET_USER], capture_output=True)
    cp = run(["sudo", "-u", TARGET_USER, "bash", "-lc", command], capture_output=True)
    brief = (cp.stdout or cp.stderr or "").strip()
    return cp.returncode == 0, brief


def setup_battery_monitor(startup_dir: Path) -> None:
    section("🔋 BATTERY MONITOR SETUP")
    src_script = startup_dir / "i3" / ".local" / "bin" / "battery-monitor.sh"
    src_service = startup_dir / "i3" / ".config" / "systemd" / "user" / "battery-monitor.service"
    dst_script = USER_HOME / ".local" / "bin" / "battery-monitor.sh"
    dst_service = USER_HOME / ".config" / "systemd" / "user" / "battery-monitor.service"

    safe_copy(src_script, dst_script)
    safe_copy(src_service, dst_service)
    if not DRY_RUN and dst_script.exists():
        try:
            dst_script.chmod(0o755)
        except Exception as ex:
            log_line(f"chmod failed {dst_script}: {ex}")

    ok1, msg1 = run_user_systemctl("daemon-reload")
    ok2, msg2 = run_user_systemctl("enable --now battery-monitor.service")
    if not ok2:
        ok3, msg3 = run_user_systemctl("start battery-monitor.service")
        if not ok3:
            log_line(f"battery service start failed: {msg3}")
    if not ok1:
        log_line(f"battery daemon-reload failed: {msg1}")
    if not ok2:
        log_line(f"battery enable failed: {msg2}")
    print(ok("battery-monitor setuped"))


# =========================
# GRUB
# =========================
def apply_grub_theme(startup_dir: Path) -> None:
    section("🎨 GRUB THEME SETUP")
    src = startup_dir / "grub"
    dst_boot = Path("/boot/grub/themes/kali")
    dst_usr = Path("/usr/share/grub/themes/kali")

    if not src.exists():
        print(warn("grub source missing; skipping"))
        return
    ok_boot = safe_copy(src, dst_boot, dirs_exist_ok=True)
    ok_usr = safe_copy(src, dst_usr, dirs_exist_ok=True)
    if ok_boot and ok_usr:
        print(ok("grub setuped"))
    else:
        print(warn("grub copy failed; continuing"))

    grub_cfg = Path("/boot/grub/grub.cfg")
    if not grub_cfg.exists():
        print(warn("/boot/grub/grub.cfg not found"))
        return

    try:
        if backup_existing(grub_cfg, move=False) is None:
            print(warn("grub.cfg backup failed; skipping grub.cfg edits"))
            return
        if DRY_RUN:
            print(info("[dry-run] set timeout=2 and default windows entry in grub.cfg"))
            return
        # timeout change: set timeout=(30|5) -> set timeout=2
        run(
            [
                "sed",
                "-i",
                "-E",
                r"s/^[[:space:]]*set timeout=(30|5)/  set timeout=2/",
                str(grub_cfg),
            ],
            capture_output=True,
        )

        windows_cp = run(
            "grep -i windows /boot/grub/grub.cfg | cut -d\"'\" -f2",
            shell=True,
            capture_output=True,
        )
        windows_entry = windows_cp.stdout.strip().splitlines()[0] if windows_cp.stdout.strip() else ""
        if windows_entry:
            run(
                [
                    "sed",
                    "-i",
                    f"s/set default=\"0\"/set default=\"{windows_entry}\"/",
                    "/boot/grub/grub.cfg",
                ],
                capture_output=True,
            )
        print(ok("grub timeout set to 2s in grub.cfg"))
    except Exception as ex:
        log_line(f"grub cfg update failed: {ex}")
        print(warn("grub timeout/default update failed; continuing"))


# =========================
# Optional apps
# =========================
def app_installed(app_name: str) -> bool:
    low = app_name.lower()
    if low == "telegram":
        return (
            Path("/opt/Telegram").exists()
            or Path("/usr/local/bin/telegram").exists()
            or shutil.which("telegram") is not None
            or shutil.which("telegram-desktop") is not None
        )
    if low in ("brave", "brave-browser", "brave-browser-nightly"):
        return shutil.which("brave-browser") is not None or shutil.which("brave-browser-nightly") is not None
    if low in ("vscode", "code"):
        return shutil.which("code") is not None
    if low == "rustscan":
        return shutil.which("rustscan") is not None
    return shutil.which(low) is not None


def normalize_app_name(script_name: str) -> str:
    stem = Path(script_name).stem
    if stem.startswith("install_"):
        stem = stem[len("install_") :]
    return stem


def discover_installers(startup_dir: Path) -> List[Tuple[str, Path]]:
    install_dir = startup_dir / "install"
    if not install_dir.exists():
        return []
    found: List[Tuple[str, Path]] = []
    for p in sorted(install_dir.iterdir()):
        if p.is_file() and p.suffix == ".sh":
            found.append((normalize_app_name(p.name), p))
    return found


def select_apps(options: List[str], statuses: Dict[str, bool]) -> List[str]:
    if not sys.stdin.isatty():
        return []
    selected = [False] * len(options)
    cursor = 0
    rendered_lines = 0
    while True:
        if rendered_lines:
            _menu_rewind(rendered_lines)
        section("🛠 OPTIONAL APPLICATIONS")
        lines = 3
        for i, app in enumerate(options):
            prefix = ">" if i == cursor else " "
            box = "[*]" if selected[i] else "[ ]"
            status = ok("[✔] already-installed") if statuses.get(app, False) else warn("[x] not-found")
            print(_fit_line(f" {prefix} {box} {app:<20} {status}"))
            lines += 1
        print(_fit_line("\n[?] press \"f\" to start (up/down + space/enter to toggle)"))
        lines += 2
        rendered_lines = lines
        key = read_key()
        if key in ("\x1b[A", "\x1bOA"):
            cursor = (cursor - 1) % len(options)
        elif key in ("\x1b[B", "\x1bOB"):
            cursor = (cursor + 1) % len(options)
        elif key in (" ", "\r", "\n"):
            selected[cursor] = not selected[cursor]
        elif key.lower() == "f":
            break
    out: List[str] = []
    for i, mark in enumerate(selected):
        if mark:
            out.append(options[i])
    return out


def optional_apps(startup_dir: Path) -> None:
    installers = discover_installers(startup_dir)
    if not installers:
        section("🛠 OPTIONAL APPLICATIONS")
        print(warn("No install/*.sh scripts found"))
        return

    # Silent/background status check before opening the menu.
    status_map: Dict[str, bool] = {}
    for app, _ in installers:
        status_map[app] = app_installed(app)

    app_names = [a for a, _ in installers]
    selected = select_apps(app_names, status_map)
    if not selected:
        print(info("No optional apps selected"))
        return

    script_map = {app: path for app, path in installers}
    for app in selected:
        script = script_map[app].resolve()
        install_root = (startup_dir / "install").resolve()
        if install_root not in script.parents:
            log_line(f"blocked unsafe installer path: {script}")
            print(warn(f"Skipping unsafe installer path: {script}"))
            continue
        print(info(f"➜ Installing {app} ..."))
        if DRY_RUN:
            print(info(f"[dry-run] bash {script}"))
            continue
        env = os.environ.copy()
        env["STARTUP_TARGET_USER"] = TARGET_USER
        env["STARTUP_TARGET_HOME"] = str(USER_HOME)
        cp = run(["bash", str(script)], capture_output=False, env=env)
        if cp.returncode == 0:
            print(ok(f"[✔] {app} installed"))
            _state_add("optional_installed", app)
            save_state()
        else:
            print(warn(f"[✖] {app} install failed (continuing)"))
            log_line(f"optional install failed: {app} ({script})")


# =========================
# Session defaults
# =========================
def set_i3_defaults() -> None:
    section("🖥️  I3 DEFAULT SESSION SETUP")
    content = "exec i3\n"
    for p in (USER_HOME / ".xinitrc", USER_HOME / ".xsession"):
        if p.exists() and backup_existing(p) is None:
            log_line(f"refusing to overwrite {p}; backup failed")
            continue
        if DRY_RUN:
            print(info(f"[dry-run] write {p}"))
            continue
        try:
            ensure_dir_owned(p.parent)
            p.write_text(content, encoding="utf-8")
            p.chmod(0o644)
            _fix_user_ownership(p)
        except Exception as ex:
            log_line(f"write failed {p}: {ex}")

    acct = Path("/var/lib/AccountsService/users") / TARGET_USER
    if acct.exists():
        try:
            txt = acct.read_text(encoding="utf-8", errors="ignore")
            if "XSession=" in txt:
                txt = "\n".join(
                    "XSession=i3" if line.startswith("XSession=") else line
                    for line in txt.splitlines()
                )
            else:
                txt += "\nXSession=i3\n"
            if backup_existing(acct) is None:
                log_line(f"refusing to overwrite {acct}; backup failed")
            elif not DRY_RUN:
                acct.write_text(txt, encoding="utf-8")
        except Exception as ex:
            log_line(f"AccountsService update failed: {ex}")

    xsession_file = Path("/etc/X11/Xsession.d/99-i3-default")
    gdm_conf = Path("/etc/gdm3/custom.conf")
    try:
        if xsession_file.exists() and backup_existing(xsession_file) is None:
            log_line(f"refusing to overwrite {xsession_file}; backup failed")
        elif not DRY_RUN:
            ensure_dir(xsession_file.parent)
            xsession_file.write_text("exec i3\n", encoding="utf-8")
            xsession_file.chmod(0o644)
    except Exception as ex:
        log_line(f"xsession default failed: {ex}")

    try:
        content0 = ""
        backup_ok = True
        if gdm_conf.exists():
            content0 = gdm_conf.read_text(encoding="utf-8", errors="ignore")
            backup_ok = backup_existing(gdm_conf) is not None
            if not backup_ok:
                log_line(f"refusing to overwrite {gdm_conf}; backup failed")
        if not DRY_RUN and backup_ok:
            if not gdm_conf.exists():
                ensure_dir(gdm_conf.parent)
            if "DefaultSession=i3.desktop" not in content0:
                content0 += "\n[daemon]\nDefaultSession=i3.desktop\n"
            gdm_conf.write_text(content0, encoding="utf-8")
    except Exception as ex:
        log_line(f"gdm custom.conf update failed: {ex}")

    run(["update-alternatives", "--install", "/usr/bin/x-session-manager", "x-session-manager", "/usr/bin/i3", "60"])
    run(["update-alternatives", "--set", "x-session-manager", "/usr/bin/i3"])

    # If brave exists, set it as default browser (best effort for target user)
    if app_installed("brave"):
        cmd1 = "xdg-settings set default-web-browser brave-browser.desktop"
        cmd2 = "gsettings set org.gnome.system.default-applications.browser exec brave-browser"
        for cmd in (cmd1, cmd2):
            if DRY_RUN:
                print(info(f"[dry-run] sudo -u {TARGET_USER} bash -lc '{cmd}'"))
            else:
                run(["sudo", "-u", TARGET_USER, "bash", "-lc", cmd], capture_output=True)

    # Auto-open grub-customizer as requested; continue if it fails.
    if DRY_RUN:
        print(info("[dry-run] grub-customizer"))
    else:
        cp = run(["grub-customizer"], capture_output=False)
        if cp.returncode != 0:
            log_line("grub-customizer failed to start")
            print(warn("grub-customizer failed to start; continuing"))


def remove_path(path: Path) -> None:
    if not path.exists() and not path.is_symlink():
        return
    try:
        if path.is_symlink() or path.is_file():
            path.unlink()
        else:
            shutil.rmtree(path)
    except Exception as ex:
        log_line(f"remove failed {path}: {ex}")


def uninstall_optional_apps() -> None:
    apps = [str(a).lower() for a in STATE.get("optional_installed", []) if isinstance(a, str)]
    if not apps:
        return
    section("↩ OPTIONAL APPS ROLLBACK")
    pkg_map = {
        "brave": ["brave-browser-nightly", "brave-browser"],
        "protonvpn": ["protonvpn", "proton-vpn-gnome-desktop"],
        "virtualbox": ["virtualbox"],
        "vscode": ["code"],
        "rustscan": ["rustscan"],
    }
    for app in apps:
        if app == "telegram":
            print(info("Removing Telegram files..."))
            if not DRY_RUN:
                remove_path(Path("/usr/local/bin/telegram"))
                remove_path(Path("/opt/Telegram"))
            continue
        pkgs = pkg_map.get(app, [app])
        print(info(f"Removing {app}: {' '.join(pkgs)}"))
        if not DRY_RUN:
            cp = run(["apt-get", "remove", "-y"] + pkgs, capture_output=True)
            if cp.returncode != 0:
                log_line(f"optional app uninstall failed {app}: {cp.stderr or cp.stdout}")


def uninstall_apt_packages(pkgs: List[str]) -> None:
    if not pkgs:
        return
    section("↩ PACKAGE ROLLBACK")
    print(info(f"Removing selected packages: {', '.join(pkgs)}"))
    if DRY_RUN:
        print(info(f"[dry-run] apt-get remove -y {' '.join(pkgs)}"))
        return
    wait_for_apt_lock(60)

    def repair_pkg_state() -> None:
        run(["dpkg", "--configure", "-a"], capture_output=True)
        run(["apt-get", "-f", "install", "-y"], capture_output=True)

    def remove_one(pkg: str) -> bool:
        cp = run(["apt-get", "remove", "-y", pkg], capture_output=True)
        if cp.returncode == 0:
            return True
        out = (cp.stderr or cp.stdout or "")
        if "dpkg was interrupted" in out.lower():
            repair_pkg_state()
            cp = run(["apt-get", "remove", "-y", pkg], capture_output=True)
            if cp.returncode == 0:
                return True
            out = (cp.stderr or cp.stdout or "")
        # purge fallback can succeed when remove does not.
        cp2 = run(["apt-get", "purge", "-y", pkg], capture_output=True)
        if cp2.returncode == 0:
            return True
        log_line(f"apt remove/purge failed for {pkg}: {out} || {cp2.stderr or cp2.stdout or ''}")
        return False

    failed: List[str] = []
    total = len(pkgs)
    for idx, pkg in enumerate(pkgs, start=1):
        pct = int((idx / total) * 100) if total else 100
        print(info(f"[{pct:>3}%] removing {pkg} ({idx}/{total})"))
        if not remove_one(pkg):
            failed.append(pkg)
    run(["apt-get", "autoremove", "-y"], capture_output=True)
    still = [pkg for pkg in pkgs if is_pkg_installed(pkg)]
    if still:
        print(warn(f"Not removed: {', '.join(still)}"))
        log_line(f"still installed after rollback remove: {', '.join(still)}")
    elif not failed:
        print(ok("Selected packages removed"))


def rollback_remove_optional_apps(apps: List[str]) -> None:
    if not apps:
        return
    section("↩ OPTIONAL APPS ROLLBACK")
    pkg_map = {
        "brave": ["brave-browser-nightly", "brave-browser"],
        "protonvpn": ["protonvpn", "proton-vpn-gnome-desktop"],
        "virtualbox": ["virtualbox"],
        "vscode": ["code"],
        "rustscan": ["rustscan"],
    }
    def repair_pkg_state() -> None:
        run(["dpkg", "--configure", "-a"], capture_output=True)
        run(["apt-get", "-f", "install", "-y"], capture_output=True)

    def remove_one(pkg: str, app_name: str) -> None:
        cp = run(["apt-get", "remove", "-y", pkg], capture_output=True)
        if cp.returncode == 0:
            return
        out = (cp.stderr or cp.stdout or "")
        if "dpkg was interrupted" in out.lower():
            repair_pkg_state()
            cp = run(["apt-get", "remove", "-y", pkg], capture_output=True)
            if cp.returncode == 0:
                return
            out = (cp.stderr or cp.stdout or "")
        cp2 = run(["apt-get", "purge", "-y", pkg], capture_output=True)
        if cp2.returncode != 0:
            log_line(f"optional app uninstall failed {app_name}: package {pkg}: {out} || {cp2.stderr or cp2.stdout or ''}")

    total = len(apps)
    for idx, app in enumerate(apps, start=1):
        pct = int((idx / total) * 100) if total else 100
        low = app.lower()
        print(info(f"[{pct:>3}%] removing {low} ({idx}/{total})"))
        if low == "telegram":
            if not DRY_RUN:
                remove_path(Path("/usr/local/bin/telegram"))
                remove_path(Path("/opt/Telegram"))
            continue
        pkgs = pkg_map.get(low, [low])
        if not DRY_RUN:
            wait_for_apt_lock(60)
            for pkg in pkgs:
                remove_one(pkg, low)


def rollback_select_removals(optional_candidates: List[str], tool_candidates: List[str]) -> Tuple[List[str], List[str]]:
    if not sys.stdin.isatty():
        return optional_candidates, tool_candidates

    rows: List[Tuple[str, str]] = [("optional", a) for a in optional_candidates] + [("tool", t) for t in tool_candidates]
    if not rows:
        return [], []
    selected = [True] * len(rows)  # default: all selected for removal
    cursor = 0

    def _menu(stdscr) -> None:
        nonlocal cursor
        curses.curs_set(0)
        stdscr.keypad(True)
        while True:
            stdscr.erase()
            r = 0
            stdscr.addstr(r, 0, "──────────────────────────────────────────────")
            r += 1
            stdscr.addstr(r, 0, "🛠 OPTIONAL APPLICATIONS")
            r += 1
            stdscr.addstr(r, 0, "──────────────────────────────────────────────")
            r += 1
            for i, (kind, name) in enumerate(rows):
                if kind != "optional":
                    continue
                prefix = ">" if i == cursor else " "
                box = "[✔]" if selected[i] else "[ ]"
                stdscr.addstr(r, 0, _fit_line(f" {prefix} {box} {name:<20} already-installed"))
                r += 1
            stdscr.addstr(r, 0, "──────────────────────────────────────────────")
            r += 1
            stdscr.addstr(r, 0, "🛠 T00L APPLICATIONS")
            r += 1
            stdscr.addstr(r, 0, "──────────────────────────────────────────────")
            r += 1
            for i, (kind, name) in enumerate(rows):
                if kind != "tool":
                    continue
                prefix = ">" if i == cursor else " "
                box = "[✔]" if selected[i] else "[ ]"
                stdscr.addstr(r, 0, _fit_line(f" {prefix} {box} {name:<20} already installed"))
                r += 1
            r += 1
            stdscr.addstr(r, 0, "[?] unselect to KEEP. press 'f' to start rollback")
            r += 1
            stdscr.addstr(r, 0, "    controls: up/down + space/enter")
            stdscr.refresh()

            ch = stdscr.getch()
            if ch in (curses.KEY_UP,):
                cursor = (cursor - 1) % len(rows)
            elif ch in (curses.KEY_DOWN,):
                cursor = (cursor + 1) % len(rows)
            elif ch in (ord(" "), 10, 13):
                selected[cursor] = not selected[cursor]
            elif ch in (ord("f"), ord("F")):
                break

    curses.wrapper(_menu)
    opt_out = [name for i, (kind, name) in enumerate(rows) if selected[i] and kind == "optional"]
    tool_out = [name for i, (kind, name) in enumerate(rows) if selected[i] and kind == "tool"]
    return opt_out, tool_out


def rollback_services() -> None:
    section("↩ SERVICE ROLLBACK")
    run_user_systemctl("disable --now battery-monitor.service")
    run_user_systemctl("daemon-reload")
    remove_path(USER_HOME / ".local" / "bin" / "battery-monitor.sh")
    remove_path(USER_HOME / ".config" / "systemd" / "user" / "battery-monitor.service")
    print(ok("Battery monitor service removed/disabled"))


def backup_rel_to_real(rel: Path) -> Path:
    system_roots = {
        "bin", "boot", "dev", "etc", "home", "lib", "lib64", "media", "mnt", "opt",
        "proc", "root", "run", "sbin", "srv", "sys", "tmp", "usr", "var",
    }
    top = rel.parts[0] if rel.parts else ""
    if top in system_roots:
        return Path("/") / rel
    return USER_HOME / rel


def restore_from_backup() -> None:
    section("↩ RESTORE FROM BACKUP")
    if not BACKUP_ROOT.exists():
        print(warn("Backup directory not found; nothing to restore"))
        return

    sessions: List[Path] = []
    for p in BACKUP_ROOT.iterdir():
        if p.is_dir() and re.fullmatch(r"\d{8}-\d{6}", p.name):
            sessions.append(p)
    restore_root = sorted(sessions, key=lambda p: p.name)[-1] if sessions else BACKUP_ROOT
    if restore_root != BACKUP_ROOT:
        print(info(f"Restoring from backup session: {restore_root.name}"))

    restored = 0
    index_path = restore_root / ".index.json"
    if index_path.exists():
        try:
            rels = json.loads(index_path.read_text(encoding="utf-8"))
        except Exception as ex:
            log_line(f"failed to read backup index {index_path}: {ex}")
            rels = []
        if isinstance(rels, list):
            # Deepest-first avoids child path conflicts if the index ever contains nested entries.
            rel_paths = sorted({str(x) for x in rels if isinstance(x, str)}, key=lambda s: len(Path(s).parts), reverse=True)
            for rel_s in rel_paths:
                b = restore_root / rel_s
                if not b.exists() and not b.is_symlink():
                    continue
                dst = backup_rel_to_real(Path(rel_s))
                if safe_move(b, dst):
                    restored += 1
            print(ok(f"Restored backup items: {restored}"))
            return

    # Legacy/fallback restore: move backed-up files/symlinks back without replacing whole parent directories.
    for dirpath, dirnames, filenames in os.walk(restore_root, topdown=False, followlinks=False):
        here = Path(dirpath)
        for name in filenames:
            b = here / name
            rel = b.relative_to(restore_root)
            if rel.as_posix() == ".index.json":
                continue
            dst = backup_rel_to_real(rel)
            if safe_move(b, dst):
                restored += 1
        for name in list(dirnames):
            b = here / name
            if b.is_symlink():
                rel = b.relative_to(restore_root)
                dst = backup_rel_to_real(rel)
                if safe_move(b, dst):
                    restored += 1
        if here != restore_root:
            try:
                here.rmdir()
            except Exception:
                pass
    print(ok(f"Restored backup items: {restored}"))


def rollback_created_files() -> None:
    section("↩ REMOVE CREATED FILES")
    created = [Path(str(p)) for p in STATE.get("created_targets", []) if isinstance(p, str)]
    removed = 0
    for p in created:
        if not p.exists() and not p.is_symlink():
            continue
        if DRY_RUN:
            print(info(f"[dry-run] remove created: {p}"))
            removed += 1
            continue
        remove_path(p)
        removed += 1
    print(ok(f"Removed created paths: {removed}"))


def rollback(startup_dir: Path) -> None:
    section("↩ ROLLBACK / RESTORE")
    load_state()
    # Rollback selection UI:
    # - Optional apps on top
    # - Tool packages on bottom
    # - All selected by default (selected => remove)
    detected_optional = [name for name, _ in discover_installers(startup_dir)]
    optional_candidates = [a for a in detected_optional if app_installed(a)]
    tool_candidates = [pkg for pkg in APT_PACKAGES if is_pkg_installed(pkg)]
    selected_optional, selected_tools = rollback_select_removals(optional_candidates, tool_candidates)

    rollback_remove_optional_apps(selected_optional)
    uninstall_apt_packages(selected_tools)
    rollback_services()
    restore_from_backup()
    rollback_created_files()

    if not DRY_RUN:
        run(["update-grub"], capture_output=True)
        run(["fc-cache", "-f"], capture_output=True)
        save_state()
    print(ok("Rollback completed"))


def make_scripts_executable() -> None:
    for root in (
        USER_HOME / ".config" / "i3" / "scripts",
        USER_HOME / ".config" / "i3blocks" / "scripts",
        USER_HOME / ".local" / "bin",
    ):
        if not root.exists():
            continue
        for f in root.rglob("*"):
            if f.is_file() and not DRY_RUN:
                try:
                    f.chmod(0o755)
                except Exception:
                    pass


def init_backup_mode() -> None:
    if DRY_RUN:
        print(info(f"[dry-run] backups enabled: {BACKUP_SESSION_DIR}"))
        return
    ensure_dir_owned(BACKUP_SESSION_DIR)
    print(info(f"Backups enabled: {BACKUP_SESSION_DIR}"))


def print_usage() -> None:
    print("Usage: python3 main.py [options]")
    print()
    print("Options:")
    print("  -r                 Rollback / restore (requires root unless --dry-run)")
    print("  --configs-only      Deploy configs only (i3/i3blocks/rofi/picom/fonts/bin)")
    print("  --dry-run, -n       Print actions without changing anything")
    print("  --verify            Verify repo + installed configs and run quick checks")
    print("  --self-test         Copy configs into a temp dir and run sanity checks")
    print("  -h, --help          Show this help")


def _file_contains(path: Path, needle: str) -> bool:
    try:
        return needle in path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return False


def verify(startup_dir: Path) -> int:
    section("✅ VERIFY / CHECK")
    ok_all = True

    # 1) Repo layout and required files.
    required = [
        startup_dir / "i3" / ".config" / "i3" / "config",
        startup_dir / "i3" / ".config" / "i3blocks" / "config",
        startup_dir / "i3" / ".config" / "i3blocks" / "scripts" / "status.sh",
        startup_dir / "i3" / ".config" / "rofi" / "config.rasi",
        startup_dir / "i3" / ".config" / "picom" / "picom.conf",
        startup_dir / "i3" / ".local" / "bin" / "battery-monitor.sh",
        startup_dir / "i3" / ".config" / "systemd" / "user" / "battery-monitor.service",
        startup_dir / "grub",
        startup_dir / "wallpaper",
        startup_dir / "install",
    ]
    for p in required:
        if not p.exists():
            print(warn(f"[repo] missing: {p}"))
            ok_all = False

    # 2) Repo config content checks (prevents the i3blocks-not-showing bug from coming back).
    repo_i3_cfg = startup_dir / "i3" / ".config" / "i3" / "config"
    repo_blocks_cfg = startup_dir / "i3" / ".config" / "i3blocks" / "config"
    if repo_i3_cfg.exists():
        want = 'status_command /bin/sh -c "i3blocks -c ~/.config/i3blocks/config"'
        if not _file_contains(repo_i3_cfg, want):
            print(warn("[repo] i3 config: expected status_command wrapper not found"))
            ok_all = False
    if repo_blocks_cfg.exists():
        if not _file_contains(repo_blocks_cfg, "markup=pango"):
            print(warn("[repo] i3blocks config: expected markup=pango not found"))
            ok_all = False
        if not _file_contains(repo_blocks_cfg, "command=bash ~/.config/i3blocks/scripts/status.sh"):
            print(warn("[repo] i3blocks config: expected bash command not found"))
            ok_all = False

    # 3) Installed config checks (only if the files exist).
    inst_i3_cfg = USER_HOME / ".config" / "i3" / "config"
    inst_blocks_cfg = USER_HOME / ".config" / "i3blocks" / "config"
    inst_status_sh = USER_HOME / ".config" / "i3blocks" / "scripts" / "status.sh"
    if inst_i3_cfg.exists():
        want = 'status_command /bin/sh -c "i3blocks -c ~/.config/i3blocks/config"'
        if not _file_contains(inst_i3_cfg, want):
            print(warn(f"[installed] i3 config missing expected status_command wrapper: {inst_i3_cfg}"))
            ok_all = False
    else:
        print(warn(f"[installed] i3 config not found (skipping): {inst_i3_cfg}"))
    if inst_blocks_cfg.exists():
        if not _file_contains(inst_blocks_cfg, "markup=pango"):
            print(warn(f"[installed] i3blocks config missing markup=pango: {inst_blocks_cfg}"))
            ok_all = False
        if not _file_contains(inst_blocks_cfg, "command=bash ~/.config/i3blocks/scripts/status.sh"):
            print(warn(f"[installed] i3blocks config missing bash command: {inst_blocks_cfg}"))
            ok_all = False
    else:
        print(warn(f"[installed] i3blocks config not found (skipping): {inst_blocks_cfg}"))
    if not inst_status_sh.exists():
        print(warn(f"[installed] status script not found (skipping): {inst_status_sh}"))

    # 4) Quick runtime checks (best effort).
    if inst_i3_cfg.exists() and shutil.which("i3"):
        cp = run(["i3", "-C", "-c", str(inst_i3_cfg)], capture_output=True)
        if cp.returncode != 0:
            print(warn("[installed] i3 -C reported config errors"))
            ok_all = False
        else:
            print(ok("[installed] i3 -C config OK"))
    elif inst_i3_cfg.exists():
        print(warn("[installed] i3 not found; skipped i3 -C check"))

    if inst_blocks_cfg.exists() and shutil.which("i3blocks"):
        if shutil.which("timeout") is None:
            print(warn("[installed] timeout(1) not found; skipped i3blocks runtime check"))
        else:
            env = os.environ.copy()
            env["HOME"] = str(USER_HOME)
            cp = run(["timeout", "2s", "i3blocks", "-c", str(inst_blocks_cfg)], env=env, capture_output=True)
            out = (cp.stdout or "") + "\n" + (cp.stderr or "")
            if "Failed to load configuration file" in out or "Command" in out and "not found" in out:
                print(warn("[installed] i3blocks produced errors (see ~/.startup_install.log)"))
                ok_all = False
            elif '"version":1' in out:
                print(ok("[installed] i3blocks output looks OK"))
            else:
                print(warn("[installed] i3blocks output did not look like i3bar JSON"))
                ok_all = False

    print(ok("VERIFY PASSED") if ok_all else warn("VERIFY FAILED"))
    return 0 if ok_all else 1


def self_test(startup_dir: Path) -> int:
    section("🧪 SELF TEST (SAFE)")
    repo_i3 = startup_dir / "i3"
    if not repo_i3.exists():
        print(err("Missing i3/ directory in repo; cannot self-test"))
        return 1

    ok_all = True
    with tempfile.TemporaryDirectory(prefix="startup-selftest-") as td:
        tmp_root = Path(td)
        tmp_home = tmp_root / "home"

        # Copy into a temp "home" so we test real file moves without touching the system.
        copies = [
            (repo_i3 / ".config" / "i3" / "config", tmp_home / ".config" / "i3" / "config"),
            (repo_i3 / ".config" / "i3blocks", tmp_home / ".config" / "i3blocks"),
            (repo_i3 / ".config" / "rofi", tmp_home / ".config" / "rofi"),
            (repo_i3 / ".config" / "picom" / "picom.conf", tmp_home / ".config" / "picom" / "picom.conf"),
            (repo_i3 / ".config" / "i3" / "scripts" / "terminal-font.sh", tmp_home / ".config" / "i3" / "scripts" / "terminal-font.sh"),
            (repo_i3 / ".config" / "systemd" / "user" / "battery-monitor.service", tmp_home / ".config" / "systemd" / "user" / "battery-monitor.service"),
            (repo_i3 / ".local", tmp_home / ".local"),
        ]
        for src, dst in copies:
            if not safe_copy(src, dst, dirs_exist_ok=True):
                print(warn(f"[self-test] copy failed: {src} -> {dst}"))
                ok_all = False

        # Basic existence checks.
        must_exist = [
            tmp_home / ".config" / "i3" / "config",
            tmp_home / ".config" / "i3blocks" / "config",
            tmp_home / ".config" / "i3blocks" / "scripts" / "status.sh",
            tmp_home / ".config" / "rofi" / "config.rasi",
            tmp_home / ".config" / "picom" / "picom.conf",
            tmp_home / ".local" / "bin" / "battery-monitor.sh",
        ]
        for p in must_exist:
            if not p.exists():
                print(warn(f"[self-test] missing after copy: {p}"))
                ok_all = False

        # Content checks.
        i3_cfg = tmp_home / ".config" / "i3" / "config"
        blocks_cfg = tmp_home / ".config" / "i3blocks" / "config"
        want = 'status_command /bin/sh -c "i3blocks -c ~/.config/i3blocks/config"'
        if i3_cfg.exists() and not _file_contains(i3_cfg, want):
            print(warn("[self-test] i3 config missing expected status_command wrapper"))
            ok_all = False
        if blocks_cfg.exists() and not _file_contains(blocks_cfg, "markup=pango"):
            print(warn("[self-test] i3blocks config missing markup=pango"))
            ok_all = False

        # Runtime checks against the temp home (best effort).
        if shutil.which("i3") and i3_cfg.exists():
            cp = run(["i3", "-C", "-c", str(i3_cfg)], capture_output=True)
            if cp.returncode != 0:
                print(warn("[self-test] i3 -C reported config errors"))
                ok_all = False
            else:
                print(ok("[self-test] i3 -C config OK"))
        else:
            print(warn("[self-test] i3 not found; skipped i3 -C check"))

        if shutil.which("i3blocks") and blocks_cfg.exists():
            if shutil.which("timeout") is None:
                print(warn("[self-test] timeout(1) not found; skipped i3blocks runtime check"))
            else:
                env = os.environ.copy()
                env["HOME"] = str(tmp_home)
                cp = run(["timeout", "2s", "i3blocks", "-c", str(blocks_cfg)], env=env, capture_output=True)
                out = (cp.stdout or "") + "\n" + (cp.stderr or "")
                if "Failed to load configuration file" in out or "Command" in out and "not found" in out:
                    print(warn("[self-test] i3blocks produced errors"))
                    ok_all = False
                elif '"version":1' in out:
                    print(ok("[self-test] i3blocks output looks OK"))
                else:
                    print(warn("[self-test] i3blocks output did not look like i3bar JSON"))
                    ok_all = False
        else:
            print(warn("[self-test] i3blocks not found; skipped i3blocks check"))

    print(ok("SELF-TEST PASSED") if ok_all else warn("SELF-TEST FAILED"))
    return 0 if ok_all else 1


def main() -> None:
    global DRY_RUN
    args = sys.argv[1:]
    if "-h" in args or "--help" in args:
        print_usage()
        return

    DRY_RUN = ("--dry-run" in args) or ("-n" in args)
    run_rollback = ("-r" in args) or ("--rollback" in args)
    configs_only = "--configs-only" in args
    run_verify = "--verify" in args
    run_self_test = "--self-test" in args

    # Only enforce root when we will actually change system state.
    if run_rollback and not DRY_RUN:
        require_root()
    if not run_rollback and not (configs_only or run_verify or run_self_test) and not DRY_RUN:
        require_root()

    startup_dir = detect_or_clone_repo()
    if startup_dir.exists():
        cleanup_python_bytecode(startup_dir)
    header(TARGET_USER, startup_dir)
    load_state()

    if run_self_test:
        sys.exit(self_test(startup_dir))
    if run_verify:
        sys.exit(verify(startup_dir))

    if run_rollback:
        rollback(startup_dir)
        return

    init_backup_mode()
    if not startup_dir.exists():
        print(err("startup repo path not found; aborting"))
        sys.exit(1)

    try:
        if configs_only:
            copy_configs(startup_dir)
            make_scripts_executable()
            print(ok("Configs deployed (configs-only mode)."))
            return

        install_packages()
        copy_configs(startup_dir)
        make_scripts_executable()
        copy_wallpapers(startup_dir)
        setup_battery_monitor(startup_dir)
        apply_grub_theme(startup_dir)
        optional_apps(startup_dir)

        section("⚙️  GRUB & SESSION DEFAULTS")
        if DRY_RUN:
            print(info("[dry-run] update-grub"))
            print(info("[dry-run] set_i3_defaults"))
        else:
            run(["update-grub"], capture_output=True)
            set_i3_defaults()

        print("\n" + "═" * 51)
        print(ok("🎉 SETUP COMPLETED"))
        print("═" * 51)
        print("Reboot recommended.")
        print("═" * 51)

        if DRY_RUN:
            print(info("[dry-run] skipping reboot prompt"))
        elif ask_yes_no("Restart now? ", default=False):
            run(["reboot"], capture_output=False)
    except Exception as ex:
        log_line(f"unexpected exception: {ex}")
        print(err("Unexpected error. Check ~/.startup_install.log"))


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n" + warn("Interrupted by user. Exiting cleanly."))
