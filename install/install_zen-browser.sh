#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

optional_detect || exit 1
optional_install curl jq

# Resolve target user information
TARGET_USER="${TARGET_USER:-${target_user:-${SUDO_USER:-${USER:-root}}}}"
TARGET_HOME="${TARGET_HOME:-${target_home:-$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || true)}}"
TARGET_GROUP="${TARGET_GROUP:-${target_group:-$(id -gn "$TARGET_USER" 2>/dev/null || true)}}"

if [[ -z "$TARGET_USER" ]]; then
    echo "Error: TARGET_USER is not set." >&2
    exit 1
fi

if [[ -z "$TARGET_HOME" ]]; then
    TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || true)"
fi

if [[ -z "$TARGET_GROUP" ]]; then
    TARGET_GROUP="$(id -gn "$TARGET_USER" 2>/dev/null || true)"
fi

[[ -d "$TARGET_HOME" ]] || {
    echo "Error: Home directory not found: $TARGET_HOME" >&2
    exit 1
}

# Detect architecture
case "$(uname -m)" in
    x86_64)
        asset="zen-x86_64.AppImage"
        ;;
    aarch64|arm64)
        asset="zen-aarch64.AppImage"
        ;;
    *)
        echo "Unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

tmpdir="$(mktemp -d)"
trap 'rm -rf -- "$tmpdir"' EXIT

# Get latest release asset
url="$(github_latest_asset_url "zen-browser/desktop" "$asset" || true)"

if [[ -z "$url" ]]; then
    echo "Could not locate the latest Zen Browser release asset ($asset)." >&2
    exit 1
fi

download_file "$url" "$tmpdir/zen.AppImage"

chmod 755 "$tmpdir/zen.AppImage"

[[ -x "$tmpdir/zen.AppImage" ]] || {
    echo "Downloaded AppImage is not executable." >&2
    exit 1
}

# Install
as_root install -d -m 755 /opt/zen-browser
as_root install -m 755 "$tmpdir/zen.AppImage" /opt/zen-browser/zen

# Symlink
as_root install -d -m 755 /usr/local/bin
as_root ln -sfn /opt/zen-browser/zen /usr/local/bin/zen

# Desktop entry
desktop_dir="$TARGET_HOME/.local/share/applications"

as_root install -d -m 755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$desktop_dir"

cat >"$tmpdir/zen-browser.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Zen Browser
GenericName=Web Browser
Comment=Browse the Web
Exec=/usr/local/bin/zen %U
TryExec=/usr/local/bin/zen
Terminal=false
Categories=Network;WebBrowser;
StartupNotify=true
Icon=web-browser
EOF

as_root install -m 644 -o "$TARGET_USER" -g "$TARGET_GROUP" "$tmpdir/zen-browser.desktop" "$desktop_dir/zen-browser.desktop"

# Verify installation
if ! command -v zen >/dev/null 2>&1; then
    echo "Zen Browser installed, but 'zen' is not in PATH." >&2
    exit 1
fi

echo "✓ Zen Browser installed successfully."
echo "Version: $(zen --version 2>/dev/null || echo 'unknown')"