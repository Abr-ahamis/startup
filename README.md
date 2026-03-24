# Startup - Kali Linux Desktop Setup Tool

Automated setup script for configuring a Kali Linux desktop environment with i3 window manager, Rofi launcher, Picom compositor, GRUB theming, and optional application installations.

## Table of Contents

- [Project Overview](#project-overview)
- [Directory Structure](#directory-structure)
- [Features](#features)
- [Usage](#usage)
- [Issues & Problems](#issues--problems)
  - [Critical Issues](#critical-issues-functional-bugs)
  - [High Priority Issues](#high-priority-functionality-issues)
  - [Medium Priority Issues](#medium-priority-securityreliability)
  - [Low Priority Issues](#low-priority-code-quality)
  - [Architecture Issues](#architecture-issues)
  - [Missing Files/Inconsistencies](#missing-filesinconsistencies)
- [Recommendations](#recommendations)
- [How to Fix Issues](#how-to-fix-issues)

---

## Project Overview

This is a **dotfiles/system setup project** for setting up a Kali Linux desktop environment with:
- **i3 window manager** with i3blocks status bar
- **Rofi** as application launcher (Aditya Shakya's theme collection)
- **Picom** for compositor effects
- **GRUB theme** customization (Kali-branded)
- **Wallpaper management**
- **Battery monitoring** via systemd user service
- **Optional application installers** (Brave, VS Code, Telegram, VirtualBox, ProtonVPN, Zen Browser)

### Supported Operations
- Full system setup with all components
- Config-only deployment (skip package installation)
- Verification of installed configurations
- Self-testing in isolated environment
- Rollback/restore from backups

---

## Directory Structure

```
startup/
├── main.py                      # Main setup script (1712 lines)
│
├── i3/                         # i3 window manager configs
│   ├── .config/
│   │   ├── i3/
│   │   │   ├── config          # i3 window manager configuration
│   │   │   └── scripts/
│   │   │       └── terminal-font.sh  # Terminal font/appearance setup
│   │   ├── i3blocks/
│   │   │   ├── config          # i3blocks status bar config
│   │   │   └── scripts/
│   │   │       └── status.sh   # Combined CPU/Mem/Network/Battery/Date status
│   │   ├── picom/
│   │   │   └── picom.conf      # Picom compositor configuration
│   │   ├── rofi/
│   │   │   ├── config.rasi     # Main Rofi config (imports launcher theme)
│   │   │   ├── launchers/      # Launcher themes and scripts
│   │   │   │   ├── launcher.sh
│   │   │   │   ├── style-1.rasi
│   │   │   │   └── shared/
│   │   │   │       ├── colors.rasi
│   │   │   │       └── fonts.rasi
│   │   │   ├── powermenu/      # Power menu themes
│   │   │   │   └── type-1/
│   │   │   │       ├── powermenu.sh
│   │   │   │       ├── style-1.rasi
│   │   │   │       └── shared/
│   │   │   ├── applets/        # Rofi applets (volume, brightness, etc.)
│   │   │   │   ├── bin/
│   │   │   │   │   ├── apps.sh
│   │   │   │   │   ├── battery.sh
│   │   │   │   │   ├── brightness.sh
│   │   │   │   │   ├── volume.sh
│   │   │   │   │   └── ...
│   │   │   │   ├── type-1/
│   │   │   │   │   ├── style-1.rasi
│   │   │   │   │   ├── style-2.rasi
│   │   │   │   │   └── style-3.rasi
│   │   │   │   └── shared/
│   │   │   ├── scripts/
│   │   │   │   ├── launcher    # Symlink to launcher script
│   │   │   │   └── powermenu_t1 # Symlink to powermenu script
│   │   │   └── colors/         # Color schemes (16 themes)
│   │   │       ├── onedark.rasi
│   │   │       ├── dracula.rasi
│   │   │       ├── nord.rasi
│   │   │       └── ... (12 more)
│   │   └── systemd/
│   │       └── user/
│   │           └── battery-monitor.service  # Systemd user service
│   └── .local/
│       ├── bin/
│       │   └── battery-monitor.sh  # Battery monitoring script
│       └── share/
│           └── fonts/               # Custom fonts (11 fonts)
│               ├── JetBrains-Mono-Nerd-Font-Complete.ttf
│               ├── Font-Awesome-7-*.otf
│               └── ...
│
├── grub/                        # GRUB theme
│   ├── theme.txt               # GRUB theme configuration
│   ├── grub-16x9.png          # 16:9 background image
│   ├── grub-4x3.png           # 4:3 background image
│   ├── select_c.png           # Selected item center
│   ├── select_e.png           # Selected item end
│   ├── select_w.png           # Selected item wide
│   └── grub_background.sh     # Legacy GRUB background script
│
├── wallpaper/                  # Wallpaper images
│   ├── wallpaper.jpg          # Primary wallpaper
│   ├── wallpaper-1.jpg        # Alternative 1
│   └── wallpaper-2.jpg        # Alternative 2
│
└── install/                    # Optional app installers
    ├── install_brave.sh       # Brave Nightly browser
    ├── install_telegram.sh    # Telegram Desktop
    ├── install_vscode.sh      # Visual Studio Code
    ├── install_virtualbox.sh   # VirtualBox
    ├── install_protonvpn.sh   # ProtonVPN
    └── install_zen-browser   # Zen Browser (missing .sh extension)
```

---

## Features

### Package Installation
- Automatic detection and installation of required packages
- APT package management with lock handling
- Support for 28+ packages including:
  - i3-wm, i3blocks, rofi, picom
  - Network monitoring tools (bmon, nload, iftop)
  - Desktop utilities (flameshot, redshift, brightnessctl)

### Configuration Deployment
- Safe copying with automatic backups
- User ownership preservation
- Symlink handling for shared resources
- Font installation

### GRUB Theme
- Custom Kali-branded GRUB theme
- Both 16:9 and 4:3 support
- Boot timeout modification
- Windows entry prioritization

### Battery Monitoring
- Systemd user service for battery notifications
- Configurable thresholds (40%, 30%, 20%, 10%)
- Plug/unplug detection

### Optional Applications
- Interactive selection menu (curses-based)
- Installation scripts for:
  - Brave Nightly Browser
  - Visual Studio Code
  - Telegram Desktop
  - VirtualBox
  - ProtonVPN
  - Zen Browser

### Rollback/Restore
- Full backup before any changes
- Interactive rollback selection
- Service cleanup
- File restoration

---

## Usage

```bash
# Full installation (requires root)
sudo python3 main.py

# Deploy configs only (no package installation)
sudo python3 main.py --configs-only

# Dry run (no changes)
sudo python3 main.py --dry-run

# Verify installation
sudo python3 main.py --verify

# Self-test in isolated environment
sudo python3 main.py --self-test

# Rollback changes
sudo python3 main.py --rollback

# Help
python3 main.py --help
```

---

## Issues & Problems

### Critical Issues (Functional Bugs)

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| 1 | main.py | 137 | **Typo**: "Walcome back Sr." | Change to "Welcome back Sir." |
| 2 | main.py | 659 | **Typo**: "ALL installed exapte:" | Change to "ALL installed except:" |
| 3 | main.py | 811 | **Grammar**: "battery-monitor setuped" | Change to "battery-monitor setup" |
| 4 | main.py | 829 | **Grammar**: "grub setuped" | Change to "grub setup" |
| 5 | install/install_zen-browser | 1 | **Wrong filename**: Missing .sh extension | Rename to install_zen-browser.sh |
| 6 | i3/config | 70 | **Hardcoded path**: Uses /home/$USER/ literal | Use ~/.config/rofi/powermenu/type-1/powermenu.sh |
| 7 | i3/config | 200 | **Tilde expansion**: ~/.config | Consistent path handling |
| 8 | picom.conf | 3 | **Deprecated backend**: backend = "xrender" | Use "glx" for better performance |

### High Priority Issues (Functionality)

| # | File | Issue | Fix |
|---|------|-------|-----|
| 9 | main.py:terminal-font.sh | **gsettings runs as root**: exec_always runs as root, but gsettings needs user context | Use sudo -u $USER bash -c 'gsettings ...' |
| 10 | main.py | **PKG_CMD_MAP incomplete**: 28 packages but only 12 mapped | Add entries for all packages or use dpkg-query only |
| 11 | main.py | **Battery monitor duplication**: Copied in both copy_configs() and setup_battery_monitor() | Consolidate into one function |
| 12 | i3/config | **Hardcoded wallpaper path**: /usr/share/backgrounds/kali/wallpaper-1.jpg | Use $HOME/Pictures/wallpaper-1.jpg or configurable |
| 13 | main.py | **No GRUB theme activation**: Copies theme but doesn't enable it | Run grub-mkconfig or update /etc/default/grub |
| 14 | install/*.sh | **Inconsistent sudo usage**: Some check id -u, others always sudo | Standardize on environment-based detection |
| 15 | install_vscode.sh | **App auto-starts**: Launches VS Code after install | Remove the nohup code & line |
| 16 | battery-monitor.sh | **0.2s battery poll**: 200ms interval is CPU intensive | Increase to 5-10 seconds |
| 17 | main.py | **apt_install continues on failure**: Continues to next package even when one fails | Add option to fail-fast |

### Medium Priority Issues (Security/Reliability)

| # | File | Issue | Fix |
|---|------|-------|-----|
| 18 | install/*.sh | **No HTTPS cert validation**: wget -q without validation | Add --no-check-certificate or proper validation |
| 19 | install/*.sh | **No GPG verification**: Packages downloaded without checksum verification | Add SHA256/PGP verification |
| 20 | main.py | **Backup overwrites by default**: backup_existing(dst, move=True) moves original | Use copy=True as default or add confirmation |
| 21 | main.py | **State file corruption risk**: JSON written without atomic writes | Use temp file + rename pattern |
| 22 | install/install_brave.sh | **Nightly only**: Always installs unstable Brave Nightly | Add --channel option for stable/beta |
| 23 | main.py | **No environment validation**: Doesn't check if on Debian/Ubuntu | Add distro detection and exit if unsupported |
| 24 | install/install_telegram.sh | **Fixed URL**: telegram.org may be blocked regionally | Add fallback mirrors |
| 25 | main.py | **apt_install retry logic**: Continues to next on failure | Log failures but don't mask them |
| 26 | i3/config | **Redshift hardcoded**: redshift -O 4500 not configurable | Add keybinding to cycle through presets |
| 27 | main.py | **Brightness device hardcoded**: intel_backlight only | Add auto-detection for other backlights |
| 28 | install/install_protonvpn.sh | **Hardcoded version**: protonvpn-stable-release_1.0.8 | Detect latest version automatically |
| 29 | main.py | **No logging of successful operations**: Only failures logged | Add success logging for audit trail |

### Low Priority Issues (Code Quality)

| # | File | Issue | Fix |
|---|------|-------|-----|
| 30 | main.py | **No docstrings**: 1700+ lines with zero documentation | Add Google-style docstrings to all functions |
| 31 | main.py | **Global STATE variable**: Makes testing difficult | Use class-based state management |
| 32 | main.py | **Magic numbers**: 60s timeout, 10000 backup attempts | Extract to named constants |
| 33 | main.py | **Inconsistent error handling**: Mixed return types | Standardize on exceptions or Result types |
| 34 | main.py | **No type hints**: Missing type annotations | Add full type hints throughout |
| 35 | i3blocks/scripts/status.sh | **Overly complex network logic**: 150+ lines for network stats | Simplify or split into modules |
| 36 | install/*.sh | **No error trapping**: || true masks failures | Proper error handling with set -e |
| 37 | main.py | **Commented dead code**: Lines 248-249 | Remove commented-out template |
| 38 | i3/config | **Duplicate section numbers**: Two sections labeled "6." | Renumber sections properly |
| 39 | main.py | **Emoji in terminal**: May not render on all terminals | Use ASCII fallbacks or detect terminal capability |
| 40 | wallpaper/ | **Only 3 images but 12 targets**: SYSTEM_WALLPAPER_TARGETS has 12 items | Add missing wallpapers or reduce targets |
| 41 | main.py | **Code duplication**: safe_copy and safe_move have overlapping logic | Extract common functionality |
| 42 | install/*.sh | **Inconsistent shebangs**: Some use #!/bin/bash, others #!/usr/bin/env bash | Standardize to #!/usr/bin/env bash |
| 43 | main.py | **Curses menu duplicates logic**: Rollback uses both read_key and curses.wrapper | Use single menu implementation |

### Architecture Issues

| # | Issue | Fix |
|---|-------|-----|
| 44 | **No config file**: All settings hardcoded | Create config.yaml or config.json for customization |
| 45 | **No rollback on partial failure**: If step 5 fails, steps 1-4 stay | Implement transaction-like behavior with rollback |
| 46 | **No update mechanism**: Only fresh install supported | Add --update flag to refresh configs |
| 47 | **No test suite**: Zero unit/integration tests | Add pytest with mocked system calls |
| 48 | **Kali-specific**: Hardcoded paths like /usr/share/backgrounds/kali/ | Make distro-agnostic with detection |
| 49 | **Monolithic main.py**: 1712 lines in single file | Split into modules (packages/, config/, grub/, etc.) |
| 50 | **No CLI argument validation**: Accepts invalid combinations | Use argparse with proper validation |

### Missing Files/Inconsistencies

| # | Issue | Fix |
|---|-------|-----|
| 51 | install/install_zen-browser missing .sh extension | Rename to install_zen-browser.sh |
| 52 | rofi/scripts/launcher is directory, not file | Should be a file or symlink |
| 53 | rofi/config.rasi references non-existent path | Fix import path to launchers/style-1.rasi |
| 54 | grub-4x3.png exists but unused | Either use it or remove from repo |
| 55 | rofi/launchers/type-1/ directory doesn't exist | Create or fix path references |

---

## Recommendations

### Phase 1: Critical Fixes (Quick Wins)
1. Fix all typos and grammar errors
2. Rename install_zen-browser to add .sh extension
3. Fix Rofi config import path
4. Fix deprecated picom backend

### Phase 2: Security & Reliability
1. Add HTTPS validation for downloads
2. Add GPG/checksum verification
3. Implement atomic file writes for state
4. Add distro detection and validation
5. Fix backup behavior (copy instead of move)

### Phase 3: Code Quality
1. Add comprehensive docstrings
2. Add type hints throughout
3. Split main.py into modules
4. Standardize error handling
5. Remove dead code and duplicates

### Phase 4: Architecture Improvements
1. Create configuration file (config.yaml)
2. Implement transaction-like rollback
3. Add update mechanism
4. Add test suite
5. Make distro-agnostic

### Phase 5: User Experience
1. Add progress bars for long operations
2. Add verbose/quiet modes
3. Add interactive configuration wizard
4. Add --config option to override defaults
5. Add color scheme selection

---

## How to Fix Issues

### 1. Fix Typo in main.py:137
```python
# Before
print("║" + "{:^50}".format("Walcome back Sr.") + "║")

# After
print("║" + "{:^50}".format("Welcome back Sir.") + "║")
```

### 2. Fix Typo in main.py:659
```python
# Before
print(warn(f"ALL installed exapte: {', '.join(still_missing)}"))

# After
print(warn(f"ALL installed except: {', '.join(still_missing)}"))
```

### 3. Rename install_zen-browser
```bash
mv install/install_zen-browser install/install_zen-browser.sh
chmod +x install/install_zen-browser.sh
```

### 4. Fix picom.conf backend
```conf
# Before
backend = "xrender";

# After
backend = "glx";
```

### 5. Fix Rofi config.rasi path
```rasi
# Before
@theme "~/.config/rofi/launchers/type-1/style-1.rasi"

# After
@theme "~/.config/rofi/launchers/style-1.rasi"
```

### 6. Fix gsettings execution (terminal-font.sh)
```bash
#!/bin/bash
# Run as target user, not root

SUDO_USER_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)

sudo -u "${SUDO_USER:-$USER}" bash -c '
    gsettings set org.gnome.Terminal.Legacy.Settings default-show-menubar false
    PROFILE=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'")
    gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE/" use-system-font false
    gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE/" font "Monospace 9"
    gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE/" use-transparent-background true
    gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE/" background-transparency-percent 30
'

systemctl --user daemon-reload
systemctl --user start battery-monitor.service
```

### 7. Add Config File Support (config.yaml)
```yaml
# config.yaml - User customization
theme:
  rofi: onedark  # or: dracula, nord, gruvbox, etc.
  grub: kali     # or: custom
  
wallpaper:
  path: ~/.local/share/wallpapers/my-wallpaper.jpg
  
packages:
  optional:
    - brave
    - vscode
  skip_default: false
    
i3:
  gaps:
    inner: 5
    outer: 5
  font_size: 8
    
battery:
  thresholds: [40, 30, 20, 10]
  poll_interval: 5  # seconds

redshift:
  temperature:
    day: 6500
    night: 4500
    warm: 3500
```

### 8. Implement Atomic State File Writes
```python
import tempfile
import os

def atomic_write_json(path: Path, data: dict) -> None:
    """Write JSON atomically using temp file + rename."""
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(data, indent=2), encoding='utf-8')
    os.replace(tmp, path)
```

### 9. Add Distro Detection
```python
def check_supported_distro() -> bool:
    """Verify running on supported distribution."""
    if not Path('/etc/debian_version').exists():
        print(err("This script requires a Debian-based distribution (Debian/Ubuntu/Kali)"))
        return False
    return True
```

### 10. Add Comprehensive Testing
```python
# tests/test_safe_copy.py
import pytest
from pathlib import Path
from unittest.mock import patch, MagicMock

def test_safe_copy_creates_backup():
    """Test that safe_copy creates backup before overwrite."""
    pass

def test_safe_copy_preserves_ownership():
    """Test that copied files retain correct ownership."""
    pass

def test_backup_existing_handles_symlinks():
    """Test backup behavior with symbolic links."""
    pass
```

---

## Contributing

When fixing issues, please follow these guidelines:

1. **Breaking Changes**: Document in CHANGELOG.md
2. **Testing**: Add tests for new functionality
3. **Documentation**: Update this README for user-facing changes
4. **Type Safety**: Maintain type hints throughout
5. **Error Handling**: Never mask failures silently

---

## License

This project contains configurations from:
- [Aditya Shakya's Rofi themes](https://github.com/adi1090x/rofi) - MIT License
- [JetBrains Mono Nerd Font](https://github.com/ryanoasis/nerd-fonts) - MIT License

---

## Author

Created for personal Kali Linux desktop setup automation.






# Startup - Multi-Distro Linux Setup Tool (Expanded Plan)

## Table of Contents
1. [Project Overview](#project-overview)
2. [Supported Distributions](#supported-distributions)
3. [File System Analysis by Distribution](#file-system-analysis-by-distribution)
4. [Component File Paths by OS](#component-file-paths-by-os)
5. [Code Modifications Required](#code-modifications-required)
6. [Multi-Distro Architecture](#multi-distro-architecture)
7. [Testing Matrix](#testing-matrix)
8. [Implementation Phases](#implementation-phases)

---

## 1. Project Overview

This is a **cross-distribution Linux desktop setup tool** that supports:
- **Ubuntu** (GNOME, all flavors)
- **Linux Mint** (Cinnamon, MATE, Xfce)
- **Parrot OS** (Security/Home editions)
- **Duban OS / ddubsOS** (NixOS-based)
- **Kali Linux** (original target)

The tool automates installation of:
- i3 window manager with i3blocks
- Rofi launcher with themes
- Picom compositor
- GRUB themes
- Battery monitoring service
- Optional applications

---

## 2. Supported Distributions

### 2.1 Distribution Matrix

| Distribution | Base | Desktop Environment | Display Manager | Package Manager |
|-------------|------|-------------------|-----------------|----------------|
| Ubuntu | Debian | GNOME/KDE/Xfce | GDM3/LightDM | apt |
| Linux Mint | Ubuntu | Cinnamon/MATE/Xfce | LightDM | apt |
| Parrot OS | Debian | MATE | GDM3 | apt |
| Duban OS | NixOS | Hyprland/GNOME/BSPWM | SDDM/GDM | nix-env |
| Kali Linux | Debian | GNOME | GDM3 | apt |

### 2.2 Detection Strategy

```python
# Detection priority order (most specific first)
DISTRO_PATTERNS = {
    'kali': r'Kali|Kali GNU/Linux',
    'parrot': r'Parrot|ParrotOS|Parrot Security',
    'linuxmint': r'Linux Mint|LMDE',
    'ubuntu': r'Ubuntu',
    'duban': r'ddubsOS|Duban|NixOS',
}

def detect_distro() -> str:
    """Detect Linux distribution from /etc/os-release"""
    os_release = Path('/etc/os-release')
    if not os_release.exists():
        return 'unknown'
    
    content = os_release.read_text().lower()
    for name, pattern in DISTRO_PATTERNS.items():
        if re.search(pattern, content, re.IGNORECASE):
            return name
    return 'debian_based'  # fallback for other Debian derivatives
```

---

## 3. File System Analysis by Distribution

### 3.1 Wallpaper Locations

#### Ubuntu
```
System-wide:  /usr/share/backgrounds/
               /usr/share/backgrounds/ubuntu/
               /usr/share/wallpapers/
User:         ~/.local/share/backgrounds/
               ~/Pictures/
```

#### Linux Mint
```
System-wide:  /usr/share/backgrounds/
               /usr/share/backgrounds/linuxmint-{release}/
               /usr/share/cinnamon-background-properties/
User:         ~/.local/share/backgrounds/
               ~/.cinnamon/backgrounds/
               ~/Pictures/
```

#### Parrot OS
```
System-wide:  /usr/share/backgrounds/
               /usr/share/images/desktop-base/
               /usr/share/parrot/
User:         ~/.local/share/backgrounds/
               ~/Pictures/
```

#### Duban OS (NixOS)
```
System-wide:  /run/current-system/sw/share/backgrounds/
               /etc/static/backgrounds/
               NixOS default: /root/result/...
User:         ~/.local/share/backgrounds/
               ~/.config/wallpapers/
```

#### Kali Linux
```
System-wide:  /usr/share/backgrounds/kali/
               /usr/share/images/desktop-base/
User:         ~/.local/share/backgrounds/
               ~/Pictures/
```

### 3.2 GRUB Theme Locations

#### Universal (all distros)
```
/boot/grub/themes/                    # Primary (Debian/Ubuntu)
/usr/share/grub/themes/               # Alternative (Fedora/Arch style)
```

#### Distribution-Specific
| Distro | GRUB Config | Update Command | Theme Format |
|--------|-------------|---------------|--------------|
| Ubuntu | /etc/default/grub | update-grub | theme.txt |
| Linux Mint | /etc/default/grub | update-grub | theme.txt |
| Parrot OS | /etc/default/grub | update-grub | theme.txt |
| Duban OS | /etc/nixos/configuration.nix | nixos-rebuild | nix attribute |
| Kali Linux | /etc/default/grub | update-grub | theme.txt |

### 3.3 Desktop Session Locations

#### X11 Sessions (Universal)
```
/usr/share/xsessions/                # System-wide .desktop files
~/.local/share/xsessions/            # User sessions (if supported)
```

#### Wayland Sessions
```
/usr/share/wayland-sessions/        # Wayland sessions
```

#### Session Files by Distro

**Ubuntu/GNOME:**
```
/usr/share/xsessions/i3.desktop     # Need to create
/etc/gdm3/custom.conf               # GDM config
```

**Linux Mint/Cinnamon:**
```
/usr/share/xsessions/i3.desktop
/etc/lightdm/lightdm.conf           # LightDM config
```

**Parrot OS:**
```
/usr/share/xsessions/i3.desktop
/etc/gdm3/custom.conf
```

**Duban OS (NixOS):**
```
# NixOS uses home-manager or configuration.nix
~/.config/nixpkgs/home.nix          # Home manager config
/etc/nixos/configuration.nix         # System config
```

### 3.4 Display Manager Configuration

#### GDM3 (GNOME - Ubuntu, Parrot, Kali)
```
Config:     /etc/gdm3/custom.conf
Sessions:   /etc/gdm3/custom.conf -> DefaultSession=i3.desktop
x-session:  /etc/X11/Xsession.d/99-i3-default
```

#### LightDM (Linux Mint, Xfce)
```
Config:     /etc/lightdm/lightdm.conf
Greeter:    /etc/lightdm/lightdm-gtk-greeter.conf
Sessions:   /etc/lightdm/users.conf
```

#### SDDM (KDE/Duban)
```
Config:     /etc/sddm.conf
Themes:     /usr/share/sddm/themes/
```

### 3.5 Systemd User Services

#### Universal
```
~/.config/systemd/user/              # User services
```

#### Service Locations by Distro (same for all)
```
battery-monitor.service:  ~/.config/systemd/user/
                          /etc/xdg/systemd/user/  (if system-wide)
```

---

## 4. Component File Paths by OS

### 4.1 Wallpaper Deployment Paths

```python
WALLPAPER_PATHS = {
    'ubuntu': {
        'system': '/usr/share/backgrounds/',
        'system_alt': '/usr/share/wallpapers/',
        'user': '~/.local/share/backgrounds/',
        'pictures': '~/Pictures/',
    },
    'linuxmint': {
        'system': '/usr/share/backgrounds/',
        'system_cinnamon': '/usr/share/cinnamon-background-properties/',
        'user': '~/.local/share/backgrounds/',
        'pictures': '~/Pictures/',
    },
    'parrot': {
        'system': '/usr/share/backgrounds/',
        'system_parrot': '/usr/share/images/desktop-base/',
        'user': '~/.local/share/backgrounds/',
        'pictures': '~/Pictures/',
    },
    'duban': {
        'system': '/run/current-system/sw/share/backgrounds/',
        'system_alt': '/etc/static/backgrounds/',
        'user': '~/.local/share/backgrounds/',
        'nixos_config': '~/.config/nixpkgs/',
    },
    'kali': {
        'system': '/usr/share/backgrounds/kali/',
        'system_alt': '/usr/share/images/desktop-base/',
        'user': '~/.local/share/backgrounds/',
        'pictures': '~/Pictures/',
    },
}
```

### 4.2 GRUB Theme Paths

```python
GRUB_PATHS = {
    'ubuntu': {
        'theme_dir': '/boot/grub/themes/startup/',
        'theme_dir_alt': '/usr/share/grub/themes/startup/',
        'grub_cfg': '/etc/default/grub',
        'grub_mkconfig': 'update-grub',
        'config_var': 'GRUB_THEME',
    },
    'linuxmint': {
        'theme_dir': '/boot/grub/themes/startup/',
        'theme_dir_alt': '/usr/share/grub/themes/startup/',
        'grub_cfg': '/etc/default/grub',
        'grub_mkconfig': 'update-grub',
        'config_var': 'GRUB_THEME',
    },
    'parrot': {
        'theme_dir': '/boot/grub/themes/startup/',
        'theme_dir_alt': '/usr/share/grub/themes/startup/',
        'grub_cfg': '/etc/default/grub',
        'grub_mkconfig': 'update-grub',
        'config_var': 'GRUB_THEME',
    },
    'duban': {
        'theme_dir': '/boot/grub/themes/startup/',  # For UEFI
        'grub_cfg': '/etc/nixos/configuration.nix',
        'grub_mkconfig': 'nixos-rebuild switch',
        'config_method': 'nix',  # Uses NixOS config
    },
    'kali': {
        'theme_dir': '/boot/grub/themes/kali/',
        'theme_dir_alt': '/usr/share/grub/themes/kali/',
        'grub_cfg': '/etc/default/grub',
        'grub_mkconfig': 'update-grub',
        'config_var': 'GRUB_THEME',
    },
}
```

### 4.3 Display Manager Configuration Paths

```python
DM_PATHS = {
    'gdm3': {  # Ubuntu, Parrot, Kali
        'config': '/etc/gdm3/custom.conf',
        'session_default': 'DefaultSession=i3.desktop',
        'xdefaults': '/etc/gdm3/custom.conf',
    },
    'lightdm': {  # Linux Mint, Xfce
        'config': '/etc/lightdm/lightdm.conf',
        'greeter': '/etc/lightdm/lightdm-gtk-greeter.conf',
        'session_default': 'user-session=i3',
        'xsession_dir': '/etc/lightdm/lightdm.d/',
    },
    'sddm': {  # Duban/KDE
        'config': '/etc/sddm.conf',
        'theme_dir': '/usr/share/sddm/themes/',
        'session_default': 'Session=i3.desktop',
    },
}
```

### 4.4 Session File Paths

```python
SESSION_PATHS = {
    'x11': {
        'system': '/usr/share/xsessions/',
        'user': '~/.local/share/xsessions/',
    },
    'wayland': {
        'system': '/usr/share/wayland-sessions/',
        'user': '~/.local/share/wayland-sessions/',
    },
}

# i3 .desktop file template
I3_DESKTOP_FILE = """[Desktop Entry]
Name=i3 Window Manager
Comment=Improved dynamic window manager
Exec=/usr/local/bin/i3-start
Type=XSession
DesktopNames=i3
```

### 4.5 Font Installation Paths

```python
FONT_PATHS = {
    'system': '/usr/share/fonts/',
    'user': '~/.local/share/fonts/',
    'user_alt': '~/.fonts/',
    'fonts_conf': '/etc/fonts/conf.d/',
}
```

---

## 5. Code Modifications Required

### 5.1 Distro Detection Module

```python
# New file: distro_detector.py
import re
from pathlib import Path
from dataclasses import dataclass
from typing import Dict, List, Optional

@dataclass
class DistroInfo:
    name: str
    family: str
    display_manager: str
    desktop_env: str
    wallpaper_system: List[Path]
    wallpaper_user: Path
    grub_theme_dir: Path
    grub_config: Path
    session_dir: Path
    uses_systemd: bool
    uses_apt: bool
    uses_nix: bool

def detect_distro() -> DistroInfo:
    """Detect distribution and return configuration paths."""
    pass

def get_wallpaper_paths(distro: DistroInfo) -> Dict[str, Path]:
    """Get wallpaper paths for specific distribution."""
    pass

def get_grub_config(distro: DistroInfo) -> Dict[str, Path]:
    """Get GRUB configuration paths."""
    pass
```

### 5.2 Distribution-Specific Configurations

#### Ubuntu Configuration
```python
UBUNTU_CONFIG = {
    'wallpaper_targets': [
        '/usr/share/backgrounds/',
        '/usr/share/wallpapers/',
    ],
    'grub_theme_var': 'GRUB_THEME',
    'grub_update': 'update-grub',
    'dm_config': '/etc/gdm3/custom.conf',
    'dm_session_var': 'DefaultSession',
}

UBUNTU_GNOME_CONFIG = {
    **UBUNTU_CONFIG,
    'desktop_env': 'gnome',
    'gsettings_schema': 'org.gnome.desktop.background',
    'terminal_profile_path': 'org.gnome.Terminal.ProfilesList',
}

UBUNTU_KDE_CONFIG = {
    **UBUNTU_CONFIG,
    'desktop_env': 'kde',
    'dm_config': '/etc/sddm.conf',
    'dm_session_var': 'Session',
}
```

#### Linux Mint Configuration
```python
MINTT_CONFIG = {
    'wallpaper_targets': [
        '/usr/share/backgrounds/',
        '/usr/share/cinnamon-background-properties/',
    ],
    'grub_theme_var': 'GRUB_THEME',
    'grub_update': 'update-grub',
    'dm_config': '/etc/lightdm/lightdm.conf',
    'dm_session_var': 'user-session',
    'desktop_env': 'cinnamon',
    # Cinnamon-specific
    'cinnamon_panel': '~/.cinnamon/configs/',
    'cinnamon_desklets': '~/.local/share/cinnamon/desklets/',
}

MINTT_MATE_CONFIG = {
    **MINTT_CONFIG,
    'desktop_env': 'mate',
    'dm_config': '/etc/lightdm/lightdm.conf',
}

MINTT_XFCE_CONFIG = {
    **MINTT_CONFIG,
    'desktop_env': 'xfce',
    'wallpaper_cmd': 'xfconf-query',
}
```

#### Parrot OS Configuration
```python
PARROT_CONFIG = {
    'wallpaper_targets': [
        '/usr/share/backgrounds/',
        '/usr/share/images/desktop-base/',
    ],
    'grub_theme_var': 'GRUB_THEME',
    'grub_update': 'update-grub',
    'dm_config': '/etc/gdm3/custom.conf',
    'dm_session_var': 'DefaultSession',
    'desktop_env': 'mate',
    # Parrot-specific
    'parrot_theme': '/usr/share/parrot/',
    'security_edition': False,  # Check for security/home
}
```

#### Duban OS (NixOS) Configuration
```python
DUBAN_CONFIG = {
    'wallpaper_targets': [
        '/run/current-system/sw/share/backgrounds/',
        '/etc/static/backgrounds/',
    ],
    'grub_config': '/etc/nixos/configuration.nix',
    'grub_update': 'nixos-rebuild switch',
    'dm_config': '/etc/sddm.conf',  # or gdm3
    'dm_session_var': 'Session',
    'desktop_env': 'hyprland',  # default
    'session_dir': '/etc/nixos/',
    'home_config': '~/.config/nixpkgs/home.nix',
    'uses_nix': True,
    'package_manager': 'nix-env',
    
    # NixOS-specific module structure
    'nix_module': '''
    # Add to configuration.nix
    environment.etc."i3/config".text = builtins.readFile /path/to/i3/config;
    services.xserver.windowManager.i3 = {
      enable = true;
      config = builtins.readFile /path/to/i3/config;
    };
    ''',
}
```

#### Kali Linux Configuration
```python
KALI_CONFIG = {
    'wallpaper_targets': [
        '/usr/share/backgrounds/kali/',
        '/usr/share/images/desktop-base/',
    ],
    'grub_theme_dir': '/boot/grub/themes/kali/',
    'grub_theme_dir_alt': '/usr/share/grub/themes/kali/',
    'grub_theme_var': 'GRUB_THEME',
    'grub_update': 'update-grub',
    'dm_config': '/etc/gdm3/custom.conf',
    'dm_session_var': 'DefaultSession',
    'desktop_env': 'gnome',
}
```

### 5.3 Wallpaper Function Refactoring

```python
def copy_wallpapers(startup_dir: Path, distro: DistroInfo) -> None:
    """Copy wallpapers to distribution-specific locations."""
    repo_wall = startup_dir / "wallpaper"
    sources = find_wallpapers(repo_wall)
    
    if not sources:
        print(warn("No wallpaper source images found."))
        return
    
    # User pictures directory
    pics = Path.home() / "Pictures"
    ensure_dir_owned(pics)
    for src in sources:
        safe_copy(src, pics / src.name)
    
    # System-wide wallpapers (distro-specific)
    for target_dir in distro.wallpaper_system:
        ensure_dir(target_dir)
        for i, src in enumerate(sources):
            dst = target_dir / f"startup-wallpaper-{i}.jpg"
            safe_copy(src, dst)
    
    # Set wallpaper using distro-specific method
    set_wallpaper(distro, sources[0])

def set_wallpaper(distro: DistroInfo, wallpaper_path: Path) -> None:
    """Set wallpaper using distro-specific method."""
    if distro.desktop_env == 'gnome':
        run([
            'sudo', '-u', TARGET_USER, 'bash', '-lc',
            f'gsettings set org.gnome.desktop.background picture-uri "file://{wallpaper_path}"'
        ])
    elif distro.desktop_env == 'cinnamon':
        run([
            'sudo', '-u', TARGET_USER, 'bash', '-lc',
            f'gsettings set org.cinnamon.desktop.background picture-uri "file://{wallpaper_path}"'
        ])
    elif distro.desktop_env == 'kde':
        # Plasma uses different method
        pass
    elif distro.uses_nix:
        # NixOS uses home-manager or configuration.nix
        pass
```

### 5.4 GRUB Theme Function Refactoring

```python
def apply_grub_theme(startup_dir: Path, distro: DistroInfo) -> None:
    """Apply GRUB theme using distribution-specific method."""
    src = startup_dir / "grub"
    
    if not src.exists():
        print(warn("GRUB source missing; skipping"))
        return
    
    if distro.uses_nix:
        apply_grub_theme_nixos(src, distro)
    else:
        apply_grub_theme_debian(src, distro)

def apply_grub_theme_debian(src: Path, distro: DistroInfo) -> None:
    """Apply GRUB theme for Debian-based distros."""
    # Copy theme to both possible locations
    theme_dirs = [
        Path('/boot/grub/themes/startup/'),
        Path('/usr/share/grub/themes/startup/'),
    ]
    
    for theme_dir in theme_dirs:
        if theme_dir.parent.exists() or theme_dir == Path('/usr/share/grub/themes/'):
            safe_copy(src, theme_dir, dirs_exist_ok=True)
            actual_theme_dir = theme_dir
            break
    
    # Update /etc/default/grub
    grub_cfg = distro.grub_config
    if not grub_cfg.exists():
        print(warn(f"GRUB config not found: {grub_cfg}"))
        return
    
    # Backup and update
    backup_existing(grub_cfg, move=False)
    
    # Add GRUB_THEME line
    content = grub_cfg.read_text()
    if f'GRUB_THEME="{actual_theme_dir}/theme.txt"' not in content:
        if 'GRUB_THEME=' in content:
            # Replace existing
            content = re.sub(
                r'GRUB_THEME=.*',
                f'GRUB_THEME="{actual_theme_dir}/theme.txt"',
                content
            )
        else:
            content += f'\nGRUB_THEME="{actual_theme_dir}/theme.txt"\n'
        
        grub_cfg.write_text(content)
    
    # Run update-grub
    run(['update-grub'], capture_output=True)
    print(ok("GRUB theme applied"))

def apply_grub_theme_nixos(src: Path, distro: DistroInfo) -> None:
    """Apply GRUB theme for NixOS."""
    nix_config = Path('/etc/nixos/configuration.nix')
    
    # Copy theme to NixOS store or /boot
    theme_dest = Path('/etc/static/grub/themes/startup/')
    ensure_dir(theme_dest)
    safe_copy(src, theme_dest, dirs_exist_ok=True)
    
    # Add to configuration.nix
    # This is complex - requires NixOS module integration
    print(warn("NixOS GRUB theme requires manual configuration.nix edit"))
```

### 5.5 Display Manager Configuration

```python
def configure_display_manager(distro: DistroInfo) -> None:
    """Configure display manager for i3 session."""
    if distro.display_manager == 'gdm3':
        configure_gdm3(distro)
    elif distro.display_manager == 'lightdm':
        configure_lightdm(distro)
    elif distro.display_manager == 'sddm':
        configure_sddm(distro)

def configure_gdm3(distro: DistroInfo) -> None:
    """Configure GDM3 for i3."""
    gdm_conf = Path('/etc/gdm3/custom.conf')
    ensure_dir(gdm_conf.parent)
    
    content = ""
    if gdm_conf.exists():
        content = gdm_conf.read_text()
        backup_existing(gdm_conf, move=False)
    
    if 'DefaultSession=i3.desktop' not in content:
        content += '\n[daemon]\nDefaultSession=i3.desktop\n'
    
    gdm_conf.write_text(content)

def configure_lightdm(distro: DistroInfo) -> None:
    """Configure LightDM for i3."""
    lightdm_conf = Path('/etc/lightdm/lightdm.conf')
    
    content = ""
    if lightdm_conf.exists():
        content = lightdm_conf.read_text()
        backup_existing(lightdm_conf, move=False)
    
    # LightDM uses user-session instead of DefaultSession
    if 'user-session=i3' not in content:
        # Add to [Seat:*] section
        content += '\n[Seat:*]\nuser-session=i3\n'
    
    lightdm_conf.write_text(content)

def configure_sddm(distro: DistroInfo) -> None:
    """Configure SDDM for i3."""
    sddm_conf = Path('/etc/sddm.conf')
    ensure_dir(sddm_conf.parent)
    
    content = ""
    if sddm_conf.exists():
        content = sddm_conf.read_text()
        backup_existing(sddm_conf, move=False)
    
    if 'Session=i3.desktop' not in content:
        content += '\n[General]\nSession=i3.desktop\n'
    
    sddm_conf.write_text(content)
```

### 5.6 Session File Creation

```python
def create_i3_session(distro: DistroInfo) -> None:
    """Create i3 .desktop session file."""
    session_content = f"""[Desktop Entry]
Name=i3 Window Manager
Comment=Dynamic window manager with minimal dependencies
Exec={USER_HOME}/.local/bin/i3-start
Type=XSession
DesktopNames=i3
X-Ubuntu-Gettext-Domain=i3
Keywords=tiling;wm;window;manager;manager;
"""
    
    if distro.desktop_env in ('gnome', 'kde'):
        # For GNOME/KDE, might need Wayland variant
        pass
    
    session_file = Path('/usr/share/xsessions/i3.desktop')
    ensure_dir(session_file.parent)
    
    if session_file.exists():
        backup_existing(session_file, move=False)
    
    session_file.write_text(session_content)
    session_file.chmod(0o644)
```

---

## 6. Multi-Distro Architecture

### 6.1 New Project Structure

```
startup/
├── main.py                      # Main entry point
├── distro/
│   ├── __init__.py
│   ├── detector.py             # Distro detection
│   ├── paths.py                # Path configuration by distro
│   ├── ubuntu.py               # Ubuntu-specific configs
│   ├── mint.py                 # Linux Mint configs
│   ├── parrot.py               # Parrot OS configs
│   ├── duban.py                # Duban/NixOS configs
│   └── kali.py                 # Kali Linux configs
├── config/
│   ├── i3.py                   # i3 configuration
│   ├── wallpaper.py             # Wallpaper handling
│   ├── grub.py                 # GRUB theme handling
│   ├── session.py              # Session management
│   └── display_manager.py      # DM configuration
├── install/
│   └── *.sh                    # App installers
├── tests/
│   ├── test_distro_detection.py
│   ├── test_paths.py
│   └── test_integration.py
├── README.md
└── config.yaml                 # User configuration
```

### 6.2 Configuration File (config.yaml)

```yaml
# config.yaml - User customization
general:
  target_distro: auto  # auto-detect or specify: ubuntu, mint, parrot, duban, kali
  dry_run: false
  verbose: true

wallpaper:
  source: ~/.startup/wallpaper/
  targets:
    user_pictures: true
    system_wide: true
  
grub:
  theme: startup  # or custom name
  timeout: 2
  default_entry: windows  # or: first, saved

i3:
  gaps:
    inner: 5
    outer: 5
  font_size: 8
  mod_key: Mod4  # or: Mod1 (Alt)

battery:
  thresholds: [40, 30, 20, 10]
  poll_interval: 5  # seconds
  notifications: true

packages:
  optional:
    - brave
    - vscode
  skip_already_installed: true

display_manager:
  auto_configure: true
  prefer: gdm3  # or: lightdm, sddm, auto
```

### 6.3 Main Function Refactoring

```python
def main() -> None:
    # Detect distribution first
    distro = detect_distro()
    print(info(f"Detected distribution: {distro.name}"))
    
    # Load configuration
    config = load_config()
    
    # Override with CLI args
    args = parse_args()
    if args.distro:
        distro = get_distro_config(args.distro)
    
    # Rest of main logic uses distro info
    install_packages(distro)
    copy_configs(distro)
    copy_wallpapers(distro)
    setup_battery_monitor(distro)
    apply_grub_theme(distro)
    configure_display_manager(distro)
    optional_apps(distro)
```

---

## 7. Testing Matrix

### 7.1 Distribution Support Matrix

| Feature | Ubuntu | Linux Mint | Parrot | Duban | Kali |
|---------|--------|-----------|--------|-------|------|
| Wallpaper copy | ✓ | ✓ | ✓ | ✓ | ✓ |
| GRUB theme | ✓ | ✓ | ✓ | ⚠️ | ✓ |
| GDM config | ✓ | N/A | ✓ | N/A | ✓ |
| LightDM config | N/A | ✓ | N/A | N/A | N/A |
| SDDM config | ⚠️ | N/A | N/A | ✓ | N/A |
| i3 session | ✓ | ✓ | ✓ | ✓ | ✓ |
| Battery monitor | ✓ | ✓ | ✓ | ✓ | ✓ |
| Package install | apt | apt | apt | nix-env | apt |
| Font install | ✓ | ✓ | ✓ | ✓ | ✓ |

Legend: ✓ = Supported, ⚠️ = Partial, N/A = Not applicable

### 7.2 Test Scenarios

```python
# tests/test_distro_detection.py
import pytest
from distro_detector import detect_distro, DistroInfo

def test_detect_ubuntu():
    """Test Ubuntu detection."""
    # Mock /etc/os-release for Ubuntu
    pass

def test_detect_linux_mint():
    """Test Linux Mint detection."""
    pass

def test_detect_parrot():
    """Test Parrot OS detection."""
    pass

def test_detect_kali():
    """Test Kali Linux detection."""
    pass

def test_detect_duban():
    """Test Duban OS detection."""
    pass

# tests/test_wallpaper.py
def test_wallpaper_paths_ubuntu():
    """Test Ubuntu wallpaper paths."""
    pass

def test_wallpaper_paths_mint():
    """Test Linux Mint wallpaper paths."""
    pass

# tests/test_integration.py
@pytest.mark.integration
def test_full_install_ubuntu():
    """Integration test for Ubuntu."""
    pass

@pytest.mark.integration  
def test_full_install_mint():
    """Integration test for Linux Mint."""
    pass
```

---

## 8. Implementation Phases

### Phase 1: Core Infrastructure
1. Create `distro_detector.py` module
2. Create path configuration modules per distro
3. Implement distro detection function
4. Add basic testing

### Phase 2: Component Refactoring
1. Refactor `copy_wallpapers()` for multi-distro
2. Refactor `apply_grub_theme()` for multi-distro
3. Refactor `set_i3_defaults()` for multi-distro
4. Add display manager detection and configuration

### Phase 3: Display Manager Support
1. Add LightDM configuration (Linux Mint)
2. Add SDDM configuration (Duban/KDE)
3. Create session files for all supported DMs

### Phase 4: Duban OS (NixOS) Support
1. Implement NixOS detection
2. Create Nix module for i3 configuration
3. Handle NixOS-specific wallpaper placement
4. Document NixOS integration

### Phase 5: Testing & Documentation
1. Write comprehensive tests
2. Update README for multi-distro support
3. Create distro-specific documentation
4. Add troubleshooting guides

---

## Appendix A: OS-Specific Notes

### A.1 Ubuntu Notes
- GDM3 is default on desktop Ubuntu
- Can have LightDM on Ubuntu Server or minimal installs
- Wallpapers in `/usr/share/backgrounds/` are often compressed
- Need to run `update-grub` after GRUB changes

### A.2 Linux Mint Notes
- LightDM is default (even with Cinnamon)
- Cinnamon has own wallpaper schema: `org.cinnamon.desktop.background`
- Can have Mate-specific configs in `/usr/share/mate-background-properties/`
- Themes go to `~/.themes/` for user or `/usr/share/themes/` system-wide

### A.3 Parrot OS Notes
- Based on Debian Testing
- Uses MATE desktop by default
- Security edition has additional tools
- Similar to Kali in many configurations

### A.4 Duban OS (NixOS) Notes
- Configuration is declarative in `/etc/nixos/configuration.nix`
- Uses `home-manager` for user configs
- Packages installed via `nix-env` or `configuration.nix`
- GRUB themes need to be in `/boot/` for EFI systems
- Wallpapers in `/run/current-system/sw/share/backgrounds/`

### A.5 Kali Linux Notes
- GDM3 is default
- Wallpapers in `/usr/share/backgrounds/kali/`
- GRUB themes traditionally in `/boot/grub/themes/kali/`
- Can use same code as Ubuntu (Debian-based)

---

## Appendix B: Reference Commands

### B.1 Distro Detection
```bash
# Check OS release
cat /etc/os-release

# Check distribution
lsb_release -a 2>/dev/null || true

# Check display manager
cat /etc/X11/default-display-manager

# Check desktop environment
echo $XDG_CURRENT_DESKTOP
```

### B.2 Wallpaper Setting
```bash
# GNOME
gsettings set org.gnome.desktop.background picture-uri "file:///path/to/image.jpg"

# Cinnamon
gsettings set org.cinnamon.desktop.background picture-uri "file:///path/to/image.jpg"

# KDE Plasma
plasma-apply-wallpaperimage /path/to/image.jpg

# XFCE
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -s /path/to/image.jpg
```

### B.3 GRUB Theme
```bash
# Update GRUB (Debian/Ubuntu)
sudo update-grub

# Update GRUB (Fedora/RHEL)
sudo grub2-mkconfig -o /boot/grub2/grub.cfg

# NixOS rebuild
sudo nixos-rebuild switch
```

---

## Appendix C: Package Differences by Distro

| Package | Ubuntu | Mint | Parrot | Duban | Kali |
|---------|--------|------|--------|-------|------|
| i3 | i3-wm | i3-wm | i3-wm | i3 | i3-wm |
| picom | picom | picom | picom | picom | picom |
| rofi | rofi | rofi | rofi | rofi | rofi |
| gdm3 | gdm3 | lightdm* | gdm3 | sddm | gdm3 |
| lightdm | lightdm | lightdm | lightdm | - | - |
| redshift | redshift | redshift | redshift | redshift | redshift |

*Linux Mint defaults to LightDM even with Cinnamon DE

---

End of Multi-Distro Support Plan
