#!/usr/bin/env bash
# Install or update Obsidian from its official GitHub AppImage release.
set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"
optional_detect || exit 1
require_download_tool || exit 1

APP_DIR=/opt/obsidian
APP_IMAGE="$APP_DIR/Obsidian.AppImage"
VERSION_FILE="$APP_DIR/version"
FALLBACK_VERSION=v1.13.4
FALLBACK_URL="https://github.com/obsidianmd/obsidian-releases/releases/download/$FALLBACK_VERSION/Obsidian-1.13.4.AppImage"

latest_version="$FALLBACK_VERSION"
latest_url="$FALLBACK_URL"
if command -v jq >/dev/null 2>&1; then
  release_json="$(curl -fsSL --retry 3 --connect-timeout 15 --max-time 60 -H 'Accept: application/vnd.github+json' https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest 2>/dev/null || true)"
  api_version="$(jq -r '.tag_name // empty' <<<"$release_json" 2>/dev/null || true)"
  api_url="$(jq -r '.assets[]? | select(.name | endswith(".AppImage")) | .browser_download_url' <<<"$release_json" 2>/dev/null | head -n1)"
  [[ "$api_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ && -n "$api_url" ]] && { latest_version="$api_version"; latest_url="$api_url"; }
fi

installed_version=""
[[ -f "$VERSION_FILE" ]] && installed_version="$(<"$VERSION_FILE")"
if [[ -x "$APP_IMAGE" && "$installed_version" == "$latest_version" ]]; then
  echo "Obsidian $installed_version is already installed."
  exit 0
fi

as_root install -d -m 755 "$APP_DIR" || exit 1
OPTIONAL_TMPDIR="${TMPDIR:-/tmp}/obsidian-install.XXXXXX"
OPTIONAL_TMPDIR="$(mktemp -d "$OPTIONAL_TMPDIR")" || exit 1
download="$OPTIONAL_TMPDIR/Obsidian.AppImage"
echo "Downloading Obsidian $latest_version..."
if ! download_file "$latest_url" "$download"; then
  echo "Obsidian download failed; the existing installation was preserved." >&2
  exit 1
fi
[[ -s "$download" ]] || { echo 'Downloaded Obsidian file is empty.' >&2; exit 1; }

if [[ -e "$APP_IMAGE" ]]; then
  as_root cp -a "$APP_IMAGE" "$APP_IMAGE.bak.$(date +%Y%m%d-%H%M%S)" || exit 1
fi
as_root install -m 755 "$download" "$APP_IMAGE" || exit 1
printf '%s\n' "$latest_version" | as_root tee "$VERSION_FILE" >/dev/null || exit 1
as_root ln -sfn "$APP_IMAGE" /usr/local/bin/obsidian || exit 1
cat >"$OPTIONAL_TMPDIR/obsidian.desktop" <<EOF
[Desktop Entry]
Name=Obsidian
Comment=Knowledge base and note-taking application
Exec=/usr/local/bin/obsidian %U
Terminal=false
Type=Application
Categories=Office;Utility;
MimeType=x-scheme-handler/obsidian;
EOF
as_root install -D -m 644 "$OPTIONAL_TMPDIR/obsidian.desktop" /usr/share/applications/obsidian.desktop || exit 1
command -v update-desktop-database >/dev/null 2>&1 && as_root update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
echo "Obsidian $latest_version installed successfully."
