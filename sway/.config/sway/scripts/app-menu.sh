#!/usr/bin/env bash
set -u

launcher="$HOME/.config/sway/scripts/launch-app.sh"
declare -a nodes=()
declare -a apps=()
declare -A icon_cache=()

add_node() { nodes+=("$1"$'\t'"$2"); }
add_app() { apps+=("$1"$'\t'"$2"$'\t'"$3"$'\t'"$4"); }

# Every menu item has a path, so new levels do not require new navigation code.
add_node '' '󰀻  Common Apps'
add_node '' '󰖟  Internet'
add_node '' '󰆍  Development'
add_node '' '󰒓  Pentesting'
add_node '' '󰝤  Media & Graphics'
add_node '' '󰌽  Linux Apps'
add_node '' '󰒓  System Tools'
add_node '󰀻  Common Apps' '  Everyday'
add_node '󰖟  Internet' '󰈹  Browsers'
add_node '󰖟  Internet' '󰞉  Communication'
add_node '󰖟  Internet' '󰒓  Network Tools'
add_node '󰆍  Development' '  IDEs & Editors'
add_node '󰆍  Development' '󰆍  Terminals & Shells'
add_node '󰆍  Development' '󰙨  Languages'
add_node '󰆍  Development' '󰒓  Build & Debug'
add_node '󰆍  Development' '󰅧  Git & Version Control'
add_node '󰆍  Development' '  Containers & Virtualization'
add_node '󰆍  Development' '󰆼  Databases'
add_node '󰆍  Development' '󰌘  API & Testing'
add_node '󰆍  Development' '󰏫  Documentation & Notes'
add_node '󰒓  Pentesting' '󰞋  Most Used Tools'
add_node '󰒓  Pentesting' '󰓛  Information Gathering'
add_node '󰒓  Pentesting' '󰖟  Web Application Analysis'
add_node '󰒓  Pentesting' '󰒓  Vulnerability Analysis'
add_node '󰒓  Pentesting' '󰆼  Database Assessment'
add_node '󰒓  Pentesting' '󰈳  Exploitation'
add_node '󰒓  Pentesting' '󰆍  Post Exploitation'
add_node '󰒓  Pentesting' '󰗚  Password Attacks'
add_node '󰒓  Pentesting' '󰤨  Wireless Testing'
add_node '󰒓  Pentesting' '󰓙  Sniffing & Spoofing'
add_node '󰒓  Pentesting' '󰆍  Reverse Engineering'
add_node '󰒓  Pentesting' '󰒒  Digital Forensics'
add_node '󰒓  Pentesting' '󰏫  Reporting'
add_node '󰒓  Pentesting' '󰒓  Security Services'
add_node '󰓛  Information Gathering' '󰍉  DNS Analysis'
add_node '󰓛  Information Gathering' '󰜁  Host Discovery'
add_node '󰓛  Information Gathering' '󰍉  Network & Port Scanning'
add_node '󰓛  Information Gathering' '󰗚  OSINT'
add_node '󰓛  Information Gathering' '󰒓  Route Analysis'
add_node '󰓛  Information Gathering' '󰆍  SMB Analysis'
add_node '󰓛  Information Gathering' '󰆍  SMTP Analysis'
add_node '󰓛  Information Gathering' '󰒓  SSL / TLS Analysis'
add_node '󰖟  Web Application Analysis' '󰌘  Web Proxies'
add_node '󰖟  Web Application Analysis' '󰍉  Web Enumeration'
add_node '󰖟  Web Application Analysis' '󰒓  Web Vulnerability Scanning'
add_node '󰖟  Web Application Analysis' '󰌘  API Security'
add_node '󰖟  Web Application Analysis' '󰈳  Web Exploitation'
add_node '󰝤  Media & Graphics' '󰏫  Image'
add_node '󰝤  Media & Graphics' '󰕧  Video'
add_node '󰝤  Media & Graphics' '󰕬  Audio'
add_node '󰝤  Media & Graphics' '󰄀  Screenshots'
add_node '󰌽  Linux Apps' '󰍹  System Monitor'
add_node '󰌽  Linux Apps' '󰋊  Disk Utility'
add_node '󰌽  Linux Apps' '󰆏  Archive Manager'
add_node '󰌽  Linux Apps' '󰒓  Software Manager'
add_node '󰌽  Linux Apps' '󰖩  Display'
add_node '󰌽  Linux Apps' '󰒓  Settings'
add_node '󰒓  System Tools' '󰖩  Network'
add_node '󰒓  System Tools' '󰂯  Bluetooth'
add_node '󰒓  System Tools' '󰕾  Audio'
add_node '󰒓  System Tools' '⏻  Power'
add_node '󰒓  System Tools' '󰒓  Desktop Controls'

# A leaf is: path, displayed name, executable candidates, launch action.
add_app '󰀻  Common Apps/  Everyday' '  Terminal' 'foot|alacritty|kitty|gnome-terminal|xterm' 'launcher:terminal'
add_app '󰀻  Common Apps/  Everyday' '  File Manager' 'nautilus|nemo|thunar|pcmanfm' 'launcher:filemanager'
add_app '󰀻  Common Apps/  Everyday' '󰏫  Text Editor' 'gnome-text-editor|gedit|mousepad|nvim|vim' 'launcher:editor'
add_app '󰀻  Common Apps/  Everyday' '󰄀  Screenshot' 'flameshot|grim' 'launcher:screenshot'
add_app '󰀻  Common Apps/  Everyday' '󰮫  Calculator' 'gnome-calculator|kcalc|qalculate-gtk' 'cmd:gnome-calculator|kcalc|qalculate-gtk'
add_app '󰖟  Internet/󰈹  Browsers' '󰈹  Firefox' 'firefox' 'cmd:firefox'
add_app '󰖟  Internet/󰈹  Browsers' '  Chromium' 'chromium|google-chrome' 'cmd:chromium|google-chrome'
add_app '󰖟  Internet/󰈹  Browsers' '  Secondary Browser' 'brave-browser|vivaldi|microsoft-edge' 'cmd:brave-browser|vivaldi|microsoft-edge'
add_app '󰖟  Internet/󰞉  Communication' '  Telegram' 'telegram-desktop|Telegram' 'launcher:telegram'
add_app '󰖟  Internet/󰞉  Communication' '󰙯  Discord' 'discord' 'cmd:discord'
add_app '󰖟  Internet/󰞉  Communication' '󰘳  Matrix' 'element-desktop|nheko' 'cmd:element-desktop|nheko'
add_app '󰖟  Internet/󰒓  Network Tools' '󰖩  Wireshark' 'wireshark' 'cmd:wireshark'
add_app '󰖟  Internet/󰒓  Network Tools' '󰌆  cURL' 'curl' 'term:curl --help'
add_app '󰖟  Internet/󰒓  Network Tools' '󰒓  Network Manager' 'nm-connection-editor|nmtui' 'cmd:nm-connection-editor|term:nmtui'
add_app '󰆍  Development/  IDEs & Editors' '󰨞  VS Code' 'code|codium' 'launcher:code'
add_app '󰆍  Development/  IDEs & Editors' '  Neovim' 'nvim' 'term:nvim'
add_app '󰆍  Development/  IDEs & Editors' '  Vim' 'vim' 'term:vim'
add_app '󰆍  Development/  IDEs & Editors' '󰆦  Geany' 'geany' 'cmd:geany'
add_app '󰆍  Development/󰆍  Terminals & Shells' '󰆍  Foot' 'foot' 'cmd:foot'
add_app '󰆍  Development/󰆍  Terminals & Shells' '  Bash' 'bash' 'term:bash'
add_app '󰆍  Development/󰆍  Terminals & Shells' '  Zsh' 'zsh' 'term:zsh'
add_app '󰆍  Development/󰆍  Terminals & Shells' '  Python' 'python|python3' 'term:python|python3'
add_app '󰆍  Development/󰙨  Languages' '  Python' 'python|python3' 'term:python|python3'
add_app '󰆍  Development/󰙨  Languages' '  Rust' 'rustc' 'term:rustc --version; exec bash'
add_app '󰆍  Development/󰙨  Languages' '  C / C++' 'gcc|g++|clang' 'term:gcc --version; exec bash'
add_app '󰆍  Development/󰙨  Languages' '  Java' 'java' 'term:java --version; exec bash'
add_app '󰆍  Development/󰙨  Languages' '  Go' 'go' 'term:go version; exec bash'
add_app '󰆍  Development/󰙨  Languages' '  JavaScript' 'node|npm' 'term:node --version; exec bash'
add_app '󰆍  Development/󰙨  Languages' '  Bash' 'bash' 'term:bash'
add_app '󰆍  Development/󰒓  Build & Debug' '󰙨  GDB' 'gdb' 'term:gdb'
add_app '󰆍  Development/󰒓  Build & Debug' '󰙨  LLDB' 'lldb' 'term:lldb'
add_app '󰆍  Development/󰒓  Build & Debug' '󰒓  CMake' 'cmake' 'term:cmake --version; exec bash'
add_app '󰆍  Development/󰒓  Build & Debug' '󰆍  Make' 'make' 'term:make --version; exec bash'
add_app '󰆍  Development/󰒓  Build & Debug' '󰆍  Ninja' 'ninja' 'term:ninja --version; exec bash'
add_app '󰆍  Development/󰅧  Git & Version Control' '󰊢  Git' 'git' 'term:git status; exec bash'
add_app '󰆍  Development/󰅧  Git & Version Control' '󰊤  GitHub' 'gh' 'term:gh'
add_app '󰆍  Development/󰅧  Git & Version Control' '󰊢  Git GUI' 'gitg|lazygit' 'cmd:gitg|term:lazygit'
add_app '󰆍  Development/  Containers & Virtualization' '󰡨  Docker' 'docker' 'term:docker ps; exec bash'
add_app '󰆍  Development/  Containers & Virtualization' '󰣨  Podman' 'podman' 'term:podman ps; exec bash'
add_app '󰆍  Development/  Containers & Virtualization' '󰡨  Distrobox' 'distrobox' 'term:distrobox list; exec bash'
add_app '󰆍  Development/  Containers & Virtualization' '󰒓  QEMU' 'qemu-system-x86_64' 'term:qemu-system-x86_64 --version; exec bash'
add_app '󰆍  Development/󰆼  Databases' '󰆼  SQLite' 'sqlite3' 'term:sqlite3'
add_app '󰆍  Development/󰆼  Databases' '󰆼  PostgreSQL' 'psql' 'term:psql'
add_app '󰆍  Development/󰆼  Databases' '󰆼  MySQL' 'mysql' 'term:mysql'
add_app '󰆍  Development/󰆼  Databases' '󰆼  Redis' 'redis-cli' 'term:redis-cli'
add_app '󰆍  Development/󰌘  API & Testing' '󰌘  Postman' 'postman' 'cmd:postman'
add_app '󰆍  Development/󰌘  API & Testing' '󰌘  HTTPie' 'http' 'term:http --help'
add_app '󰆍  Development/󰌘  API & Testing' '󰌘  Insomnia' 'insomnia' 'cmd:insomnia'
add_app '󰆍  Development/󰏫  Documentation & Notes' '󰠮  Obsidian' 'obsidian' 'launcher:obsidian'

add_app '󰒓  Pentesting/󰞋  Most Used Tools' '󰞋  Nmap' 'nmap' 'term:nmap --help'
add_app '󰒓  Pentesting/󰞋  Most Used Tools' '󰞋  Burp Suite' 'burpsuite' 'cmd:burpsuite'
add_app '󰒓  Pentesting/󰞋  Most Used Tools' '󰞋  Metasploit' 'msfconsole' 'term:msfconsole'
add_app '󰒓  Pentesting/󰞋  Most Used Tools' '󰞋  Wireshark' 'wireshark' 'cmd:wireshark'
add_app '󰒓  Pentesting/󰞋  Most Used Tools' '󰞋  Gobuster' 'gobuster' 'term:gobuster'
add_app '󰒓  Pentesting/󰞋  Most Used Tools' '󰞋  SQLmap' 'sqlmap' 'term:sqlmap --help'
add_app '󰒓  Pentesting/󰓛  Information Gathering' '󰍉  dig' 'dig' 'term:dig'
add_app '󰒓  Pentesting/󰓛  Information Gathering' '󰍉  dnsrecon' 'dnsrecon' 'term:dnsrecon --help'
add_app '󰒓  Pentesting/󰓛  Information Gathering' '󰍉  dnsenum' 'dnsenum' 'term:dnsenum --help'
add_app '󰒓  Pentesting/󰓛  Information Gathering' '󰜁  arp-scan' 'arp-scan' 'term:arp-scan --help'
add_app '󰒓  Pentesting/󰓛  Information Gathering' '󰜁  netdiscover' 'netdiscover' 'term:netdiscover'
add_app '󰒓  Pentesting/󰓛  Information Gathering' '󰜁  fping' 'fping' 'term:fping --help'
add_app '󰒓  Pentesting/󰓛  Information Gathering' '󰍉  Nmap' 'nmap' 'term:nmap'
add_app '󰒓  Pentesting/󰓛  Information Gathering' '󰍉  Masscan' 'masscan' 'term:masscan --help'
add_app '󰒓  Pentesting/󰓛  Information Gathering' '󰍉  Unicornscan' 'unicornscan' 'term:unicornscan'
add_app '󰒓  Pentesting/󰖟  Web Application Analysis' '󰌘  Burp Suite' 'burpsuite' 'cmd:burpsuite'
add_app '󰒓  Pentesting/󰖟  Web Application Analysis' '󰌘  Caido' 'caido' 'cmd:caido'
add_app '󰒓  Pentesting/󰖟  Web Application Analysis' '󰌘  OWASP ZAP' 'zaproxy' 'cmd:zaproxy'
add_app '󰒓  Pentesting/󰖟  Web Application Analysis' '󰍉  Gobuster' 'gobuster' 'term:gobuster'
add_app '󰒓  Pentesting/󰖟  Web Application Analysis' '󰍉  ffuf' 'ffuf' 'term:ffuf'
add_app '󰒓  Pentesting/󰖟  Web Application Analysis' '󰍉  dirsearch' 'dirsearch' 'term:dirsearch'
add_app '󰒓  Pentesting/󰖟  Web Application Analysis' '󰒓  Nikto' 'nikto' 'term:nikto'
add_app '󰒓  Pentesting/󰖟  Web Application Analysis' '󰒓  nuclei' 'nuclei' 'term:nuclei'
add_app '󰒓  Pentesting/󰖟  Web Application Analysis' '󰌘  Postman' 'postman' 'cmd:postman'
add_app '󰒓  Pentesting/󰖟  Web Application Analysis' '󰆼  sqlmap' 'sqlmap' 'term:sqlmap'
add_app '󰒓  Pentesting/󰖟  Web Application Analysis' '󰈳  commix' 'commix' 'term:commix'
add_app '󰒓  Pentesting/󰒓  Vulnerability Analysis' '󰒓  OpenVAS / Greenbone' 'gvm-start|openvas' 'cmd:gvm-start|cmd:openvas'
add_app '󰒓  Pentesting/󰒓  Vulnerability Analysis' '󰒓  Nuclei' 'nuclei' 'term:nuclei'
add_app '󰒓  Pentesting/󰒓  Vulnerability Analysis' '󰒓  Nikto' 'nikto' 'term:nikto'
add_app '󰒓  Pentesting/󰒓  Vulnerability Analysis' '󰒓  Lynis' 'lynis' 'term:lynis'
add_app '󰒓  Pentesting/󰆼  Database Assessment' '󰆼  SQLmap' 'sqlmap' 'term:sqlmap'
add_app '󰒓  Pentesting/󰈳  Exploitation' '󰈳  Metasploit' 'msfconsole' 'term:msfconsole'
add_app '󰒓  Pentesting/󰈳  Exploitation' '󰈳  SearchSploit' 'searchsploit' 'term:searchsploit'
add_app '󰒓  Pentesting/󰗚  Password Attacks' '󰗚  John the Ripper' 'john' 'term:john'
add_app '󰒓  Pentesting/󰗚  Password Attacks' '󰗚  Hashcat' 'hashcat' 'term:hashcat'
add_app '󰒓  Pentesting/󰗚  Password Attacks' '󰗚  Hydra' 'hydra' 'term:hydra'
add_app '󰒓  Pentesting/󰤨  Wireless Testing' '󰤨  Aircrack-ng' 'aircrack-ng' 'term:aircrack-ng'
add_app '󰒓  Pentesting/󰤨  Wireless Testing' '󰤨  Kismet' 'kismet' 'cmd:kismet'
add_app '󰒓  Pentesting/󰓙  Sniffing & Spoofing' '󰖩  Wireshark' 'wireshark' 'cmd:wireshark'
add_app '󰒓  Pentesting/󰆍  Reverse Engineering' '󰆍  Ghidra' 'ghidraRun' 'cmd:ghidraRun'
add_app '󰒓  Pentesting/󰆍  Reverse Engineering' '󰆍  Radare2' 'radare2|r2' 'term:radare2|term:r2'
add_app '󰒓  Pentesting/󰒒  Digital Forensics' '󰒒  Autopsy' 'autopsy' 'cmd:autopsy'
add_app '󰒓  Pentesting/󰒒  Digital Forensics' '󰒒  Binwalk' 'binwalk' 'term:binwalk'
add_app '󰒓  Pentesting/󰏫  Reporting' '󰠮  Obsidian' 'obsidian' 'launcher:obsidian'
add_app '󰒓  Pentesting/󰏫  Reporting' '󰏫  CherryTree' 'cherrytree' 'cmd:cherrytree'

add_app '󰝤  Media & Graphics/󰏫  Image' '󰄀  GIMP' 'gimp' 'cmd:gimp'
add_app '󰝤  Media & Graphics/󰕧  Video' '󰕧  VLC' 'vlc' 'cmd:vlc'
add_app '󰝤  Media & Graphics/󰕬  Audio' '󰕬  Audacity' 'audacity' 'cmd:audacity'
add_app '󰝤  Media & Graphics/󰄀  Screenshots' '󰄀  Screenshot' 'flameshot|grim' 'launcher:screenshot'
add_app '󰌽  Linux Apps/󰍹  System Monitor' '󰍹  System Monitor' 'gnome-system-monitor|btop|htop' 'cmd:gnome-system-monitor|term:btop|term:htop'
add_app '󰌽  Linux Apps/󰋊  Disk Utility' '󰋊  Disk Utility' 'gnome-disk-utility|gparted' 'cmd:gnome-disk-utility|cmd:gparted'
add_app '󰌽  Linux Apps/󰆏  Archive Manager' '󰆏  Archive Manager' 'file-roller|xarchiver' 'cmd:file-roller|cmd:xarchiver'
add_app '󰌽  Linux Apps/󰒓  Software Manager' '󰒓  Software Manager' 'pamac-manager|gnome-software' 'cmd:pamac-manager|cmd:gnome-software'
add_app '󰌽  Linux Apps/󰖩  Display' '󰖩  Display' 'wdisplays|arandr' 'cmd:wdisplays|cmd:arandr'
add_app '󰌽  Linux Apps/󰒓  Settings' '󰒓  Settings' 'gnome-control-center|systemsettings' 'cmd:gnome-control-center|cmd:systemsettings'
add_app '󰒓  System Tools/󰖩  Network' '󰖩  Wi-Fi menu' 'nm-connection-editor|nmtui' 'cmd:nm-connection-editor|term:nmtui'
add_app '󰒓  System Tools/󰂯  Bluetooth' '󰂯  Bluetooth menu' 'blueman-manager|bluetoothctl' 'cmd:blueman-manager|term:bluetoothctl'
add_app '󰒓  System Tools/󰕾  Audio' '󰕾  Volume and brightness' 'pamixer|brightnessctl' 'term:pamixer --get-volume; exec bash'
add_app '󰒓  System Tools/⏻  Power' '⏻  Power menu' 'systemctl' 'term:systemctl --help; exec bash'
add_app '󰒓  System Tools/󰒓  Desktop Controls' '󰒓  Sway Settings' 'swaymsg' 'term:swaymsg -t get_tree | less'

has_command() {
  local candidate
  local -a candidates
  IFS='|' read -ra candidates <<<"$1"
  for candidate in "${candidates[@]}"; do command -v "$candidate" >/dev/null 2>&1 && return 0; done
  return 1
}

desktop_icon_for() {
  local checks="$1" candidate desktop icon desktop_dir
  local -a candidates
  [[ ${icon_cache[$checks]+set} ]] && { printf '%s' "${icon_cache[$checks]}"; return 0; }
  IFS='|' read -ra candidates <<<"$checks"
  for candidate in "${candidates[@]}"; do
    for desktop_dir in \
      "$HOME/.local/share/applications" \
      "${XDG_DATA_HOME:-$HOME/.local/share}/applications" \
      /usr/local/share/applications \
      /usr/share/applications \
      /var/lib/flatpak/exports/share/applications; do
      [[ -d "$desktop_dir" ]] || continue
      while IFS= read -r desktop; do
        icon="$(awk -v command="$candidate" -F= '
          $1 == "Icon" { icon = $2 }
          $1 == "Exec" {
            executable = $2
            sub(/^[[:space:]]*/, "", executable)
            sub(/[[:space:]].*/, "", executable)
            sub(/^.*\//, "", executable)
          }
          END { if (executable == command) print icon }
        ' "$desktop")"
        [[ -n "$icon" ]] || continue
        icon_cache["$checks"]="$icon"
        printf '%s' "$icon"
        return 0
      done < <(find "$desktop_dir" -type f -name '*.desktop' -print 2>/dev/null)
    done
  done
  icon_cache["$checks"]=''
  return 1
}

section_icon_for() {
  case "$1" in
    *'Common Apps') printf '%s' 'applications-utilities' ;;
    *Internet) printf '%s' 'applications-internet' ;;
    *Development) printf '%s' 'applications-development' ;;
    *Pentesting) printf '%s' 'applications-security' ;;
    *'Media & Graphics') printf '%s' 'applications-multimedia' ;;
    *'Linux Apps') printf '%s' 'applications-system' ;;
    *'System Tools') printf '%s' 'preferences-system' ;;
    *) printf '%s' 'folder' ;;
  esac
}

path_available() {
  local app_path app_label app_checks app_action
  while IFS=$'\t' read -r app_path app_label app_checks app_action; do
    [[ "$app_path" == "$1" || "$app_path" == "$1/"* ]] && has_command "$app_checks" && return 0
  done < <(printf '%s\n' "${apps[@]}")
  return 1
}

menu_for() {
  local current_path="$1" node_path node_label app_path app_label app_checks app_action child_path icon entry_label entry_icon
  local -a entries=()
  while IFS=$'\t' read -r node_path node_label; do
    if [[ -z "$current_path" && "$node_path" != */* ]] || [[ "$node_path" == "$current_path"/* && "${node_path#"$current_path"/}" != */* ]]; then
      child_path="${node_path:+$node_path/}$node_label"
      if path_available "$child_path"; then
        entries+=("$node_label"$'\t'"$(section_icon_for "$node_label")")
      fi
    fi
  done < <(printf '%s\n' "${nodes[@]}")
  while IFS=$'\t' read -r app_path app_label app_checks app_action; do
    if [[ "$app_path" == "$current_path" ]] && has_command "$app_checks"; then
      icon="$(desktop_icon_for "$app_checks" || true)"
      [[ -n "$icon" ]] || icon='application-x-executable'
      entries+=("$app_label"$'\t'"$icon")
    fi
  done < <(printf '%s\n' "${apps[@]}")
  [[ -n "$current_path" ]] && entries+=('󰅬  Back'$'\t''go-previous')
  ((${#entries[@]})) || return 1
  for entry in "${entries[@]}"; do
    IFS=$'\t' read -r entry_label entry_icon <<<"$entry"
    if [[ -n "$entry_icon" ]]; then
      printf '%s\0icon\x1f%s\n' "$entry_label" "$entry_icon"
    else
      printf '%s\n' "$entry_label"
    fi
  done | wofi --dmenu --prompt "󰍉  Applications${current_path:+ / $current_path}" --insensitive --matching fuzzy --sort_order alphabetical --style "$HOME/.config/wofi/style.css"
}

launch_action() {
  local action="$1" action_part candidate
  local -a action_parts
  IFS='|' read -ra action_parts <<<"$action"
  for action_part in "${action_parts[@]}"; do
    case "$action_part" in
      launcher:*) exec "$launcher" "${action_part#launcher:}" ;;
      cmd:*) candidate="${action_part#cmd:}"; command -v "$candidate" >/dev/null 2>&1 && exec "$candidate" ;;
      term:*) exec foot bash -lc "${action_part#term:}; exec bash" ;;
    esac
  done
}

current_path=''
while :; do
  choice="$(menu_for "$current_path" || true)"
  [[ -n "$choice" ]] || exit 0
  if [[ "$choice" == *Back ]]; then current_path="${current_path%/*}"; continue; fi
  next_path="${current_path:+$current_path/}$choice"
  has_child=0
  for node in "${nodes[@]}"; do [[ "$node" == "$next_path"$'\t'* ]] && has_child=1 && break; done
  if ((has_child)); then current_path="$next_path"; continue; fi
  while IFS=$'\t' read -r app_path app_label app_checks app_action; do
    [[ "$app_path" == "$current_path" && "$app_label" == "$choice" ]] && launch_action "$app_action" && exit 0
  done < <(printf '%s\n' "${apps[@]}")
done