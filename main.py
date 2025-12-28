#!/usr/bin/env python3
"""
startup_setup_full.py

Final upgraded script:
 - Ensures battery-monitor script & service installed for target user
 - Runs systemctl --user commands as target user with XDG_RUNTIME_DIR
 - Prints a clear colorized checklist of the final battery/service steps (commands + status)
 - Single Y/N prompt to install Telegram, Brave (nightly), RustScan
 - Always applies GRUB theme
 - Sets i3 as default (writes ~/.xinitrc & ~/.xsession + AccountsService best-effort)
"""
from __future__ import annotations
import os
import sys
import shutil
import subprocess
import datetime
from pathlib import Path
from typing import List, Optional, Tuple
import pwd

# ---------- config ----------
REPO_URL = "https://github.com/Abr-ahamis/startup.git"
REPO_DIR_NAME = "startup"
DRY_RUN = False
TIMESTAMP = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")

APT_PACKAGES = [
    "i3","i3-wm", "i3blocks", "rofi", "xdotool", "dex", "acpi", "upower",
    "xfce4-power-manager", "i3lock", "xss-lock", "pulseaudio-utils",
    "brightnessctl", "feh", "picom", "fonts-font-awesome", "git", "rsync",
    "unzip", "curl", "wget", "grub-customizer", "timeshift"
]

# ---------- colors ----------
CSI = "\033["
RESET = CSI + "0m"
BOLD = CSI + "1m"
GREEN = CSI + "32m"
YELLOW = CSI + "33m"
RED = CSI + "31m"
CYAN = CSI + "36m"
CHECK = "✔"
CROSS = "✖"

def color_ok(s): return f"{GREEN}{s}{RESET}"
def color_warn(s): return f"{YELLOW}{s}{RESET}"
def color_err(s): return f"{RED}{s}{RESET}"
def color_info(s): return f"{CYAN}{s}{RESET}"

# ---------- helpers ----------
def run(cmd, check=False, capture_output=True, shell=False, env=None) -> subprocess.CompletedProcess:
    if DRY_RUN:
        print(color_info(f"[DRY-RUN CMD] {cmd}"))
        class D:
            returncode = 0
            stdout = ""
            stderr = ""
        return D()
    if isinstance(cmd, (list, tuple)):
        cmd_display = " ".join(map(str, cmd))
    else:
        cmd_display = str(cmd)
    print(color_info(f"[CMD] {cmd_display}"))
    try:
        completed = subprocess.run(cmd, check=check, capture_output=capture_output, text=True, shell=shell, env=env)
        return completed
    except subprocess.CalledProcessError as e:
        return e

def ensure_dir(p: Path):
    if not p.exists():
        if not DRY_RUN:
            p.mkdir(parents=True, exist_ok=True)
        print(color_info(f"MKDIR: {p}"))

def backup_existing(p: Path) -> Optional[Path]:
    if not p.exists():
        return None
    bak = p.with_name(p.name + ".backup")
    if bak.exists():
        bak = p.with_name(p.name + f".backup.{TIMESTAMP}")
    try:
        if not DRY_RUN:
            shutil.move(str(p), str(bak))
        print(color_info(f"BACKUP: {p} -> {bak}"))
        return bak
    except Exception as e:
        print(color_warn(f"BACKUP-FAIL: {p}: {e}"))
        return None

def safe_copy(src: Path, dst: Path, backup_if_exists=True, dirs_exist_ok=False) -> bool:
    if not src.exists():
        print(color_warn(f"SKIP (missing): {src}"))
        return False
    ensure_dir(dst.parent)
    if dst.exists():
        if backup_if_exists:
            backup_existing(dst)
        else:
            if dst.is_dir():
                if not DRY_RUN:
                    shutil.rmtree(dst, ignore_errors=True)
            else:
                if not DRY_RUN:
                    dst.unlink()
    try:
        if src.is_dir():
            if not DRY_RUN:
                shutil.copytree(src, dst, dirs_exist_ok=dirs_exist_ok)
            print(color_ok(f"COPY: {src} -> {dst}"))
        else:
            if not DRY_RUN:
                shutil.copy2(src, dst)
            print(color_ok(f"COPY: {src} -> {dst}"))
        # try chown to user later (best-effort)
        return True
    except Exception as e:
        print(color_warn(f"COPY-FAIL: {src} -> {dst}: {e}"))
        return False

# ---------- environment ----------
def get_target_user() -> str:
    sudo_user = os.environ.get("SUDO_USER")
    if sudo_user:
        return sudo_user
    return os.environ.get("USER", "root")

TARGET_USER = get_target_user()
try:
    USER_HOME = Path(pwd.getpwnam(TARGET_USER).pw_dir)
except Exception:
    USER_HOME = Path(os.environ.get("HOME", "/root"))

print(color_info(f"Target user: {TARGET_USER}, home: {USER_HOME}"))

# ---------- repo detect/clone (kept simple) ----------
def detect_or_clone_repo() -> Path:
    cwd = Path.cwd()
    print(color_info(f"Working dir: {cwd}"))
    if (cwd / "i3").is_dir() and (cwd / "grub").is_dir() and (cwd / "wallpaper").is_dir():
        print(color_info("Using current dir as repo"))
        return cwd
    if (cwd / REPO_DIR_NAME).is_dir():
        return cwd / REPO_DIR_NAME
    target = cwd / REPO_DIR_NAME
    if DRY_RUN:
        print(color_info(f"DRY-RUN would git clone {REPO_URL} -> {target}"))
        return target
    if shutil.which("git") is None:
        print(color_warn("git not available; please place repo at ./startup"))
        return target
    r = run(["git", "clone", "--depth", "1", REPO_URL, str(target)], capture_output=True)
    if getattr(r, "returncode", 1) != 0:
        print(color_warn("git clone returned non-zero; continuing"))
    return target

# ---------- core copy ----------
def copy_core_configs(startup_dir: Path):
    print(color_info("COPYING: repo -> user config (backups if present)"))
    repo_i3 = startup_dir / "i3"
    safe_copy(repo_i3 / ".config" / "i3" / "config", USER_HOME / ".config" / "i3" / "config")
    safe_copy(repo_i3 / ".config" / "i3" / "scripts" / "terminal-font.sh", USER_HOME / ".config" / "i3" / "scripts" / "terminal-font.sh")
    safe_copy(repo_i3 / ".config" / "i3blocks", USER_HOME / ".config" / "i3blocks", dirs_exist_ok=True)
    safe_copy(repo_i3 / ".config" / "rofi", USER_HOME / ".config" / "rofi", dirs_exist_ok=True)
    safe_copy(repo_i3 / ".config" / "picom" / "picom.conf", USER_HOME / ".config" / "picom" / "picom.conf")
    # local bin
    src_local_bin = repo_i3 / ".local" / "bin"
    dst_local_bin = USER_HOME / ".local" / "bin"
    ensure_dir(dst_local_bin)
    if src_local_bin.exists():
        for f in sorted(src_local_bin.iterdir()):
            safe_copy(f, dst_local_bin / f.name)
    # fonts
    src_fonts = repo_i3 / ".local" / "share" / "fonts"
    dst_fonts = USER_HOME / ".local" / "share" / "fonts"
    ensure_dir(dst_fonts)
    if src_fonts.exists():
        for f in sorted(src_fonts.iterdir()):
            safe_copy(f, dst_fonts / f.name)
    # rofi system theme
    src_rofi = repo_i3 / "usr" / "share" / "rofi" / "themes" / "Adapta-Nokto.rasi"
    if src_rofi.exists():
        safe_copy(src_rofi, Path("/usr/share/rofi/themes/Adapta-Nokto.rasi"))
    # wallpapers
    repo_wall = startup_dir / "wallpaper"
    ensure_dir(USER_HOME / "Pictures")
    for name in ("wallpaper.jpg", "wallpaper-1.jpg", "wallpaper-2.jpg"):
        s = repo_wall / name
        if s.exists():
            safe_copy(s, USER_HOME / "Pictures" / name)
    # system rotate
    backgrounds_dir = Path("/usr/share/backgrounds/kali")
    ensure_dir(backgrounds_dir)
    mapping = [
        ("wallpaper-1.jpg", "login.svg"),
        ("wallpaper.jpg", "kali-maze-16x9.jpg"),
        ("wallpaper-2.jpg", "kali-tiles-16x9.jpg"),
        ("wallpaper-1.jpg", "kali-waves-16x9.png"),
        ("wallpaper.jpg", "kali-oleo-16x9.png"),
        ("wallpaper-2.jpg", "kali-tiles-purple-16x9.jpg"),
        ("wallpaper-1.jpg", "wallpaper-1.jpg"),
        ("wallpaper-1.jpg", "login-blurred"),
    ]
    for src_name, dst_name in mapping:
        s = repo_wall / src_name
        dst = backgrounds_dir / dst_name
        if dst.exists():
            bak = dst.with_name(dst.name + f".{TIMESTAMP}.bak")
            try:
                if not DRY_RUN:
                    dst.rename(bak)
                print(color_ok(f"SYS-RENAME: {dst} -> {bak}"))
            except Exception as e:
                print(color_warn(f"SYS-RENAME FAIL: {dst}: {e}"))
        if s.exists():
            try:
                if not DRY_RUN:
                    shutil.copy2(s, dst)
                print(color_ok(f"SYS-COPY: {s} -> {dst}"))
            except Exception as e:
                print(color_warn(f"SYS-COPY FAIL: {s} -> {dst}: {e}"))

# ---------- battery monitor install & systemd user commands ----------
def install_battery_monitor_and_enable(startup_dir: Path) -> List[Tuple[str, bool, str]]:
    """
    Returns list of tuples (command_str, success_bool, brief_output)
    Commands executed (as target user with XDG_RUNTIME_DIR=/run/user/UID):
      - chmod +x ~/.local/bin/battery-monitor.sh
      - systemctl --user daemon-reload
      - systemctl --user enable battery-monitor.service
      - systemctl --user start battery-monitor.service
    """
    results = []
    uid = pwd.getpwnam(TARGET_USER).pw_uid
    runtime_dir = f"/run/user/{uid}"

    repo_script = startup_dir / "i3" / ".local" / "bin" / "battery-monitor.sh"
    repo_service = startup_dir / "i3" / ".config" / "systemd" / "user" / "battery-monitor.service"

    dst_script = USER_HOME / ".local" / "bin" / "battery-monitor.sh"
    dst_service = USER_HOME / ".config" / "systemd" / "user" / "battery-monitor.service"

    # copy script and service
    if repo_script.exists():
        ensure_dir(dst_script.parent)
        safe_copy(repo_script, dst_script)
        # chmod +x
        try:
            if not DRY_RUN:
                dst_script.chmod(0o755)
            results.append((f"chmod +x {dst_script}", True, "executable set"))
            print(color_ok(f"chmod +x {dst_script}"))
        except Exception as e:
            results.append((f"chmod +x {dst_script}", False, str(e)))
            print(color_warn(f"chmod fail {dst_script}: {e}"))
    else:
        results.append((f"chmod +x {dst_script}", False, "script missing in repo"))
        print(color_warn(f"battery script missing: {repo_script}"))

    if repo_service.exists():
        ensure_dir(dst_service.parent)
        safe_copy(repo_service, dst_service)
        results.append((f"copy {repo_service} -> {dst_service}", True, "copied"))
        print(color_ok(f"COPY: {repo_service} -> {dst_service}"))
    else:
        results.append((f"copy {repo_service} -> {dst_service}", False, "service missing in repo"))
        print(color_warn(f"battery service missing: {repo_service}"))

    # helper to run a systemctl --user command as the target user
    def run_user_systemctl(cmd_args: str) -> Tuple[bool, str]:
        # full command string (run under sudo -u)
        # use bash -lc to allow chaining and environment
        full = f"XDG_RUNTIME_DIR={runtime_dir} systemctl --user {cmd_args}"
        if DRY_RUN:
            print(color_info(f"DRY-RUN: sudo -u {TARGET_USER} bash -lc \"{full}\""))
            return True, "DRY-RUN"
        # execute via sudo -u TARGET_USER bash -lc
        cp = run(["sudo", "-u", TARGET_USER, "bash", "-lc", full], capture_output=True)
        rc = getattr(cp, "returncode", 1)
        out = (getattr(cp, "stdout", "") or "").strip()
        err = (getattr(cp, "stderr", "") or "").strip()
        brief = out if out else err
        return rc == 0, brief

    # daemon-reload
    ok, brief = run_user_systemctl("daemon-reload")
    results.append(("systemctl --user daemon-reload", ok, brief or "no output"))
    print(color_ok("systemctl --user daemon-reload" if ok else color_warn("systemctl --user daemon-reload failed")))

    # enable
    ok, brief = run_user_systemctl("enable --now battery-monitor.service")
    results.append(("systemctl --user enable --now battery-monitor.service", ok, brief or "no output"))
    print(color_ok("systemctl --user enable --now battery-monitor.service" if ok else color_warn("enable --now failed")))

    # start (if enable combined didn't start/failed, attempt start explicitly)
    if not results[-1][1]:
        ok, brief = run_user_systemctl("start battery-monitor.service")
        results.append(("systemctl --user start battery-monitor.service", ok, brief or "no output"))
        print(color_ok("systemctl --user start battery-monitor.service" if ok else color_warn("start failed")))

    return results

# ---------- small app installers ----------
def install_telegram(startup_dir: Path):
    print(color_info("Installing Telegram (best-effort)"))
    tfile = Path("/tmp/tsetup.tar.xz")
    if DRY_RUN:
        print(color_info("DRY-RUN: download/extract telegram"))
        return
    run(["wget", "-q", "https://telegram.org/dl/desktop/linux", "-O", str(tfile)])
    opt = Path("/opt/Telegram")
    if opt.exists():
        backup_existing(opt)
        shutil.rmtree(opt, ignore_errors=True)
    ensure_dir(opt)
    run(["tar", "-xf", str(tfile), "-C", str(opt), "--strip-components=1"])
    tbin = opt / "Telegram"
    if tbin.exists():
        try:
            tbin.chmod(0o755)
        except Exception:
            pass
        link = Path("/usr/local/bin/telegram")
        if link.exists() or link.is_symlink():
            try:
                link.unlink()
            except Exception:
                pass
        try:
            link.symlink_to(tbin)
            print(color_ok(f"SYMLINK: {link} -> {tbin}"))
        except Exception as e:
            print(color_warn(f"SYMLINK FAIL: {e}"))

def install_brave_nightly():
    print(color_info("Installing Brave (nightly) (best-effort)"))
    if DRY_RUN:
        print(color_info("DRY-RUN: brave install"))
        return
    run('curl -fsS https://dl.brave.com/install.sh | CHANNEL=nightly bash', shell=True)
    run(["apt", "install", "-y", "brave-browser-nightly"])

def install_rustscan():
    print(color_info("Installing RustScan (best-effort)"))
    deb = Path("/tmp/rustscan.deb")
    url = "https://github.com/RustScan/RustScan/releases/latest/download/rustscan_amd64.deb"
    if DRY_RUN:
        print(color_info("DRY-RUN: rustscan install"))
        return
    run(["wget", "-q", url, "-O", str(deb)])
    if deb.exists():
        run(["dpkg", "-i", str(deb)])
        run(["apt", "install", "-f", "-y"])

# ---------- set i3 default ----------
def set_i3_default():
    print(color_info("Setting i3 as default: writing ~/.xinitrc & ~/.xsession"))
    xinit = USER_HOME / ".xinitrc"
    xsession = USER_HOME / ".xsession"
    content = "exec i3\n"
    for p in (xinit, xsession):
        if p.exists():
            backup_existing(p)
        try:
            if not DRY_RUN:
                p.write_text(content)
                p.chmod(0o644)
            print(color_ok(f"WRITE: {p} -> exec i3"))
        except Exception as e:
            print(color_warn(f"WRITE FAIL: {p}: {e}"))
    # AccountsService best-effort
    acct = Path("/var/lib/AccountsService/users") / TARGET_USER
    if acct.exists():
        try:
            txt = acct.read_text()
            if "XSession=" in txt:
                txt = "\n".join([line if not line.startswith("XSession=") else "XSession=i3" for line in txt.splitlines()])
            else:
                txt = txt + "\nXSession=i3\n"
            if not DRY_RUN:
                backup_existing(acct)
                acct.write_text(txt)
            print(color_ok(f"MODIFY: {acct} -> XSession=i3"))
        except Exception as e:
            print(color_warn(f"AccountsService update failed: {e}"))
    else:
        print(color_info("AccountsService entry not present; may need to select i3 once in greeter."))

# ---------- single yes/no prompt ----------
def prompt_yes_no(question: str, default: bool = False) -> bool:
    yes = {"y", "yes"}
    no = {"n", "no"}
    default_str = "Y/n" if default else "y/N"
    try:
        while True:
            ans = input(f"{question} [{default_str}]: ").strip().lower()
            if ans == "" and default:
                return True
            if ans == "" and not default:
                return False
            if ans in yes:
                return True
            if ans in no:
                return False
    except KeyboardInterrupt:
        print(color_warn("Interrupted; assuming 'no'"))
        return False

# ---------- main ----------
def main():
    if os.geteuid() != 0:
        print(color_err("Please run as root: sudo python3 startup_setup_full.py"))
        sys.exit(1)

    print(color_info("Starting setup..."))
    startup_dir = detect_or_clone_repo()
    if not startup_dir.exists():
        print(color_warn("startup repo not found locally; many steps may be no-op."))

    # apt installs (best-effort)
    if not DRY_RUN and shutil.which("apt"):
        print(color_info("APT: update"))
        run(["apt", "update"])
        print(color_info("APT: install packages (best-effort)"))
        run(["apt", "install", "-y"] + APT_PACKAGES)
    else:
        print(color_info("Skipping apt installs (DRY-RUN or apt missing)"))

    # copy configs/wallpapers
    copy_core_configs(startup_dir)

    # ensure battery monitor script/service are installed and run systemctl user commands
    service_results = install_battery_monitor_and_enable(startup_dir)

    # apply grub theme (always)
    apply_grub_theme(startup_dir)

    # chmod +x for other scripts, i3 restart if running
    # set executables
    for p in (USER_HOME / ".config" / "i3" / "scripts", USER_HOME / ".local" / "bin"):
        if p.exists():
            for f in p.rglob("*"):
                if f.is_file():
                    try:
                        if not DRY_RUN:
                            f.chmod(0o755)
                    except Exception:
                        pass

    # attempt i3 restart if running for user
    p = run(["pgrep", "-u", TARGET_USER, "-x", "i3"])
    if getattr(p, "returncode", 1) == 0:
        if not DRY_RUN:
            run(["sudo", "-u", TARGET_USER, "i3-msg", "restart"])

    # single prompt for apps
    if prompt_yes_no("Install Telegram, Brave (nightly) and RustScan now?", default=False):
        install_telegram(startup_dir)
        install_brave_nightly()
        install_rustscan()
    else:
        print(color_info("Skipping app installations."))

    # set i3 default
    set_i3_default()

    # final checklist print (battery/service related)
    print("\n" + BOLD + "Final battery-monitor/service checklist:" + RESET)
    # Always show these four lines (presence, chmod, reload, enable/start) and whether they succeeded
    # Build expected commands and map to results collected above
    expected = [
        (f"Script path exists and executable", f"chmod +x {USER_HOME}/.local/bin/battery-monitor.sh"),
        (f"Service file copied to user systemd folder", f"{USER_HOME}/.config/systemd/user/battery-monitor.service"),
        ("Service reloaded", "systemctl --user daemon-reload"),
        ("Service enabled & started", "systemctl --user enable --now battery-monitor.service"),
    ]

    # Determine statuses from service_results
    # service_results is a list of tuples (command_str, success_bool, brief_output)
    results_map = {cmd: (ok, brief) for (cmd, ok, brief) in service_results if isinstance(cmd, str)}

    # Present each expected line:
    # For the first two, check actual files present & executable
    # For reload/enable, query results_map
    # 1) script exists & executable
    script_path = USER_HOME / ".local" / "bin" / "battery-monitor.sh"
    ok_script = script_path.exists() and (script_path.stat().st_mode & 0o111)
    if ok_script:
        print(f"{color_ok(CHECK)} Script path exists and executable")
        print(f"    chmod +x {script_path}")
    else:
        print(f"{color_warn(CROSS)} Script path missing or not executable")
        print(f"    chmod +x {script_path}")

    # 2) service file present
    svc_path = USER_HOME / ".config" / "systemd" / "user" / "battery-monitor.service"
    if svc_path.exists():
        print(f"{color_ok(CHECK)} Service file copied")
        print(f"    {svc_path}")
    else:
        print(f"{color_warn(CROSS)} Service file missing")
        print(f"    Expected: {svc_path}")

    # 3) reload & 4) enable/start - look up results_map
    reload_key = "systemctl --user daemon-reload"
    enable_key = "systemctl --user enable --now battery-monitor.service"
    start_key = "systemctl --user start battery-monitor.service"

    if reload_key in results_map:
        ok, brief = results_map[reload_key]
        if ok:
            print(f"{color_ok(CHECK)} Service reloaded")
            print(f"    systemctl --user daemon-reload")
        else:
            print(f"{color_warn(CROSS)} Service reload failed")
            print(f"    systemctl --user daemon-reload -> {brief}")
    else:
        print(f"{color_warn(CROSS)} Service reload not attempted (no user session?)")
        print(f"    systemctl --user daemon-reload")

    if enable_key in results_map:
        ok, brief = results_map[enable_key]
        if ok:
            print(f"{color_ok(CHECK)} Service enabled & running")
            print(f"    systemctl --user enable --now battery-monitor.service")
        else:
            # check if start was attempted afterwards
            if start_key in results_map:
                ok2, brief2 = results_map[start_key]
                if ok2:
                    print(f"{color_ok(CHECK)} Service started")
                    print(f"    systemctl --user start battery-monitor.service")
                else:
                    print(f"{color_warn(CROSS)} Enable/start failed")
                    print(f"    enable -> {brief}; start -> {brief2}")
            else:
                print(f"{color_warn(CROSS)} Enable/start failed: {brief}")
                print(f"    systemctl --user enable --now battery-monitor.service")
    else:
        # maybe start exists
        if start_key in results_map and results_map[start_key][0]:
            print(f"{color_ok(CHECK)} Service started")
            print(f"    systemctl --user start battery-monitor.service")
        else:
            print(f"{color_warn(CROSS)} Service enable/start not attempted or failed")
            print(f"    systemctl --user enable --now battery-monitor.service")

    print("\n" + color_info("Setup finished. If service commands failed because the user has no active session,"))
    print(color_info(f"run as that user after login:"))
    print(color_info(f"  XDG_RUNTIME_DIR=/run/user/<UID> systemctl --user daemon-reload"))
    print(color_info(f"  XDG_RUNTIME_DIR=/run/user/<UID> systemctl --user enable --now battery-monitor.service"))
    print(color_ok("Done."))

# ---------- helpers used earlier ----------
def detect_or_clone_repo() -> Path:
    cwd = Path.cwd()
    if (cwd / "i3").is_dir() and (cwd / "grub").is_dir() and (cwd / "wallpaper").is_dir():
        return cwd
    if (cwd / REPO_DIR_NAME).is_dir():
        return cwd / REPO_DIR_NAME
    target = cwd / REPO_DIR_NAME
    if DRY_RUN:
        return target
    if shutil.which("git") is None:
        return target
    run(["git", "clone", "--depth", "1", REPO_URL, str(target)])
    return target

def apply_grub_theme(startup_dir: Path):
    print(color_info("Applying GRUB theme (no prompt)"))
    repo_grub = startup_dir / "grub"
    dst_boot = Path("/boot/grub/themes/kali")
    dst_usr = Path("/usr/share/grub/themes")
    ensure_dir(dst_boot)
    ensure_dir(dst_usr)
    if repo_grub.exists():
        try:
            if dst_boot.exists():
                shutil.rmtree(dst_boot, ignore_errors=True)
            shutil.copytree(repo_grub, dst_boot, dirs_exist_ok=True)
            print(color_ok(f"COPY: {repo_grub} -> {dst_boot}"))
        except Exception as e:
            print(color_warn(f"GRUB COPY FAIL: {e}"))
        try:
            shutil.copytree(repo_grub, dst_usr / "kali", dirs_exist_ok=True)
            print(color_ok(f"COPY: {repo_grub} -> {dst_usr}/kali"))
        except Exception as e:
            print(color_warn(f"GRUB COPY /usr FAIL: {e}"))
    else:
        print(color_warn("No grub/ directory found; skipping"))

if __name__ == "__main__":
    main()
