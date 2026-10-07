# Sway / Omarchy-Style Keybindings

This reference follows the Omarchy-style keybinding layout while documenting the bindings and utilities currently configured by this project. It is based on [`sway/.config/sway/config`](sway/.config/sway/config), [`lib/95-gnome-keybindings.sh`](lib/95-gnome-keybindings.sh), the launcher scripts, and the i3blocks configuration.

**Super** means the Windows / Meta key. GNOME shortcuts are listed separately because they only apply when the installer configures a GNOME session. This guide describes configured behavior; it does not add the additional Omarchy bindings that are not present in this project's config.

---

# Navigating

| Hotkey | Function |
| --- | --- |
| **Super + Space** | Application launcher |
| **Super + Alt + Space** | Application launcher |
| **Super + D** | Application launcher |
| **Super + Escape** | System / power menu |
| **Super + Ctrl + L** | Lock computer |
| **Super + W** | Close focused window |
| **Ctrl + Alt + Delete** | Close all application windows without logging out |
| **Super + T** | Toggle window between tiling and floating |
| **Super + J / E** | Toggle split layout orientation |
| **Super + O** | Toggle sticky + floating window |
| **Super + F** | Fullscreen |
| **Super + 1…9 / 0** | Jump to workspaces 1…9 / 10 |
| **Super + Tab / Shift + Tab** | Next / previous workspace |
| **Super + Ctrl + Tab** | Return to former workspace |
| **Super + Shift + 1…9 / 0** | Move window to workspace |
| **Super + Shift + Alt + 1…9 / 0** | Move window to workspace without following |
| **Super + Shift + Alt + Arrow** | Move workspace to directional monitor |
| **Super + Arrow** | Move focus to window in direction |
| **Super + Shift + Arrow** | Move focused window in direction |
| **Super + Equal / Minus** | Shrink / grow window width |
| **Super + Shift + Equal / Minus** | Grow / shrink window height |
| **Super + Alt + Equal / Minus** | Shrink / grow window width by 5 pixels |
| **Super + Ctrl + Equal / Minus** | Shrink / grow window width by 30 pixels |
| **Super + Left Mouse** | Drag window |
| **Super + Right Mouse** | Resize window |
| **Super + Scroll Wheel** | Cycle through workspaces |

---

# Window grouping

Window grouping shortcuts are not currently configured. Super+J and Super+E change split orientation; they do not group windows.

---

# Scratchpad

| Hotkey | Function |
| --- | --- |
| **Super + S** | Show scratchpad |
| **Super + Alt + S** | Move focused window to scratchpad |

---

# Focus and window cycling

| Hotkey | Function |
| --- | --- |
| **Super + Arrow** | Focus window in that direction |
| **Super + H / L** | Focus left / right |
| **Alt + Tab** | Cycle focus forward |
| **Alt + Shift + Tab** | Cycle focus backward |
| **Ctrl + Alt + Tab** | Cycle focus forward through monitors |
| **Ctrl + Alt + Shift + Tab** | Cycle focus backward through monitors |

---

# Display and screen navigation

Monitor zoom and scaling shortcuts are not currently configured.

| Hotkey | Function |
| --- | --- |
| **Super + Ctrl + Delete** | Turn off display outputs while keeping the session active |
| **Super + Shift + Alt + Arrow** | Move workspace to the output in that direction |

---

# System controls

System utilities use the **Super + Ctrl** family where configured.

| Hotkey | Function |
| --- | --- |
| **Super + Ctrl + A** | Audio and brightness controls |
| **Super + Ctrl + B** | Bluetooth controls |
| **Super + Ctrl + W** | Wi-Fi controller |
| **Super + Ctrl + T** | Activity monitor — btop |
| **Super + Ctrl + C** | Screenshot |
| **Super + Ctrl + V** | Clipboard manager |
| **Super + Ctrl + N** | Toggle night light |
| **Super + Ctrl + Shift + L** | Lock computer (alternate binding) |
| **Ctrl + Alt + I** | IP / network information |
| **Ctrl + Alt + V** | Audio and brightness controls |
| **Ctrl + Alt + W** | Wi-Fi controller |
| **Ctrl + Alt + B** | Bluetooth controls |
| **XF86RFKill** | Toggle Wi-Fi radio |

### Direct system actions

| Hotkey | Function |
| --- | --- |
| **Ctrl + Alt + R** | Reload Sway configuration |
| **Ctrl + Alt + E** | Exit Sway / log out |
| **Ctrl + Alt + L** | Lock computer |
| **Ctrl + Alt + P** | Open power menu |

---

# Launching applications

| Hotkey | Function |
| --- | --- |
| **Super + Return** | Preferred terminal |
| **Super + Alt + Return** | Secondary terminal |
| **Super + Shift + Return** | Preferred browser |
| **Super + Shift + F** | Preferred file manager |
| **Super + Shift + T** | Telegram |
| **Super + Shift + N** | Neovim / LazyVim in the preferred terminal |
| **Super + Shift + Alt + N** | Preferred GUI text editor |
| **Super + Shift + C** | VS Code / VSCodium |
| **Super + Shift + O** | Obsidian |
| **Print** | Screenshot |
| **Super + D / Space** | Application launcher |
| **Super + K / Shift + F1** | Keybinding help |

### Application fallback order

The launcher uses the first installed program from each role.

| App role | Preference order |
| --- | --- |
| **Terminal** | foot → alacritty → kitty → gnome-terminal → xterm |
| **Secondary terminal** | gnome-terminal → foot → alacritty → kitty → xterm |
| **Neovim** | `~/.local/bin/nvim` (newer per-user build when the distro package is too old), then `nvim` from PATH |
| **Browser** | brave-browser → firefox → google-chrome → chromium |
| **File manager** | nautilus → nemo → thunar → pcmanfm |
| **Text editor** | gnome-text-editor → gedit → mousepad |
| **Code editor** | code → codium |
| **Notes** | obsidian |
| **Screenshot** | flameshot GUI → grim |
| **Telegram** | `/opt/Telegram/Telegram` → telegram-desktop → Telegram |

---

# Clipboard

| Hotkey | Function |
| --- | --- |
| **Super + Ctrl + V** | Open clipboard history |

Super+C and Super+X are not assigned globally in the Sway config, so ordinary application copy and cut shortcuts remain available.

---

# Capture

| Hotkey | Function |
| --- | --- |
| **Print** | Screenshot using Flameshot, or Grim if Flameshot is unavailable |
| **Super + Ctrl + C** | Screenshot using the same fallback |

A separate capture control menu and screen-recording binding are not currently configured.

---

# Notifications

| Hotkey | Function |
| --- | --- |
| **Super + ,** | Dismiss latest notification |
| **Super + Shift + ,** | Dismiss all notifications |
| **Super + Ctrl + ,** | Toggle notification silence / Do Not Disturb |

---

# Audio

| Hotkey / Key | Function |
| --- | --- |
| **Volume Down** | Decrease default audio sink volume by 5% |
| **Volume Up** | Increase default audio sink volume by 5% |
| **Mute** | Toggle default audio sink mute |
| **Alt + Volume Down** | Decrease volume by 1% |
| **Alt + Volume Up** | Increase volume by 1% |
| **Super + Ctrl + A** | Open audio and brightness controls |

---

# Brightness and display

| Hotkey / Key | Function |
| --- | --- |
| **Brightness Down** | Decrease brightness by 2% |
| **Brightness Up** | Increase brightness by 2% |
| **Shift + Brightness Down** | Set brightness to minimum |
| **Shift + Brightness Up** | Set brightness to maximum |
| **Alt + Brightness Down** | Decrease brightness by 1% |
| **Alt + Brightness Up** | Increase brightness by 1% |
| **Super + Ctrl + A** | Open audio and brightness controls |
| **Super + Ctrl + N** | Toggle night light |
| **Super + Ctrl + Delete** | Turn off display outputs |

---

# Power

| Hotkey | Function |
| --- | --- |
| **Super + Escape** | Open power / system menu |
| **Ctrl + Alt + P** | Open power / system menu |
| **Shift + Ctrl + P** | Open power menu in a terminal |
| **Ctrl + Shift + Super + Q** | Power off |
| **Ctrl + Shift + Super + A** | Reboot |
| **Ctrl + Shift + Super + S** | Suspend |

---

# GNOME shortcuts

The installer also configures these shortcuts when it sets up an active GNOME session. They apply in GNOME, not Sway.

| Hotkey | Function |
| --- | --- |
| **Super + Return** | Preferred terminal |
| **Super + Alt + Return** | Secondary terminal |
| **Super + Shift + F** | File manager |
| **Super + Shift + Return** | Browser |
| **Super + Shift + T** | Telegram |
| **Super + Shift + N** | Neovim / LazyVim in the preferred terminal |
| **Super + Shift + Alt + N** | Preferred GUI text editor |
| **Super + Shift + S** | Screenshot |
| **Super + Shift + C** | VS Code |
| **Shift + F1** | Keybinding help |
| **XF86RFKill** | Toggle Wi-Fi radio |
| **Super + W** | Close focused window |
| **Super + D** | Open GNOME application menu |
| **Super + F** | Toggle fullscreen |
| **Super + Left / Right** | Switch workspace left / right |
| **Super + Shift + Left / Right** | Move window to workspace left / right |
| **Ctrl + Alt + L** | Lock screen |

---

# i3blocks / status bar interactions

| Bar block | Left click | Right click | Wheel |
| --- | --- | --- | --- |
| **Wi-Fi / Network interface** | Open that interface's controller | — | — |
| **Network speed / VPN interface** | Open Wi-Fi controller | — | — |
| **Bluetooth** | Open Bluetooth menu | Blueman Manager | — |
| **IP** | Open network information | — | — |
| **Volume** | Open volume/brightness menu | Toggle mute | Adjust volume by 5% |
| **Brightness** | Open volume/brightness menu | — | Adjust brightness by 5% |
| **Clipboard** | Open clipboard manager | Clear clipboard history | — |
| **RAM / Disk** | Open btop | — | — |
| **Updates** | Show read-only package-update information | — | — |
| **Power** | Open power menu | — | — |

The Wi-Fi/network bar provides separate interface slots. Clicking a Wi-Fi slot opens the controller directly for that adapter; clicking an Ethernet slot opens its network controller.

---

# Menus and utility scripts

| Script | Purpose |
| --- | --- |
| `sway/.config/sway/scripts/launch-app.sh` | Application launcher and fallback selection |
| `sway/.local/bin/setup-neovim.sh` | Ensure a LazyVim-compatible Neovim version and back up existing Neovim data before setting up the starter config; use `--launch` to open it after setup |
| `sway/.config/sway/scripts/close-all-windows.sh` | Close all application windows without logging out |
| `sway/.config/sway/scripts/power-menu.sh` | System / power menu |
| `sway/.config/sway/scripts/key-help-wofi.sh` | Searchable keybinding help |
| `sway/.config/sway/scripts/toggle-night-light.sh` | Toggle night light |
| `sway/.config/i3blocks/scripts/menu/wifi_menu.sh` | Wi-Fi interface controller |
| `sway/.config/i3blocks/scripts/menu/network_interface_menu.sh` | Ethernet/network controller |
| `sway/.config/i3blocks/scripts/menu/bt_menu.sh` | Bluetooth controller |
| `sway/.config/i3blocks/scripts/menu/ip_menu.sh` | IP/network information |
| `sway/.config/i3blocks/scripts/menu/vol-brigh_menu.sh` | Audio / brightness / night-light controls |
| `sway/.config/i3blocks/scripts/menu/power_menu.sh` | Terminal power menu |
| `sway/.config/i3blocks/scripts/bar/wifi_click.sh` | Route a bar click to the selected interface controller |
| `sway/.local/bin/startup-session.sh` | Start session services, applets, clipboard, wallpaper, and helpers |
| `sway/.local/bin/polkit-agent.sh` | Start an available PolicyKit authentication agent |

---

# Keybinding design

The configured layout uses these modifier families:

### Super

Navigation, window management, workspace switching, scratchpad, and resize controls.

### Super + Shift

Application launching and moving windows to workspaces.

### Super + Ctrl

System and desktop controls, including audio, Bluetooth, Wi-Fi, btop, screenshots, clipboard, display, and night light.

### Super + Alt

Secondary terminal, alternate launcher, scratchpad, monitor movement, and fine window resizing.

### Ctrl + Shift + Super

Power off, reboot, and suspend.

---

# Destructive shortcuts

| Shortcut | Action |
| --- | --- |
| **Ctrl + Alt + Delete** | Closes all application windows across the Sway session |
| **Ctrl + Alt + E** | Logs out of Sway |
| **Ctrl + Shift + Super + Q** | Powers off |
| **Ctrl + Shift + Super + A** | Reboots |
| **Ctrl + Shift + Super + S** | Suspends |

These actions remain separate from ordinary navigation and application-launching shortcuts.
