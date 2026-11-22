#!/usr/bin/env bash
# 20-install-lu.sh — install the latest Locally Uncensored from GitHub Releases.
#
#   ./scripts/20-install-lu.sh                      # latest .deb, SHA-256 verified
#   ./scripts/20-install-lu.sh --version v3.1.2     # pin a release
#   ./scripts/20-install-lu.sh --appimage           # ~/ai/bin/LU.AppImage instead of the .deb
#
# The .deb is the right choice on Ubuntu: apt resolves WebKitGTK/GTK from the archive, and the
# package can bring its own AppArmor profile. The AppImage needs libfuse2 and cannot carry one.
set -euo pipefail

REPO="PurpleDoubleD/locally-uncensored"
DL="${LU_DL:-$HOME/ai/downloads}"
FORMAT="deb"
VERSION=""

die() { echo "error: $*" >&2; exit 1; }
say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version)  VERSION="${2:-}"; [ -n "$VERSION" ] || die "--version needs a tag, e.g. v3.1.2"; shift 2 ;;
    --appimage) FORMAT="appimage"; shift ;;
    -h|--help)  usage ;;
    *)          die "unknown argument: $1 (try --help)" ;;
  esac
done

[ "$(uname -m)" = "x86_64" ] || die "only amd64 assets are published ($(uname -m) here)"
command -v curl >/dev/null || die "curl missing: sudo apt-get install -y curl ca-certificates"
command -v python3 >/dev/null || die "python3 missing: sudo apt-get install -y python3"

mkdir -p "$DL"

say "Release"
if [ -n "$VERSION" ]; then
  api="https://api.github.com/repos/$REPO/releases/tags/$VERSION"
else
  api="https://api.github.com/repos/$REPO/releases/latest"
fi
json=$(curl -fsSL -H 'Accept: application/vnd.github+json' "$api") \
  || die "GitHub API request failed: $api (rate limited? try again, or pass --version)"

# One line out of python3: tag, asset URL, checksum URL. No jq dependency.
read -r tag asset_url sums_url < <(printf '%s' "$json" | LU_FORMAT="$FORMAT" python3 -c '
import json, os, sys
d = json.load(sys.stdin)
fmt = os.environ["LU_FORMAT"]
wanted = "_amd64.deb" if fmt == "deb" else "_amd64.AppImage"
assets = {a["name"]: a["browser_download_url"] for a in d.get("assets", [])}
pick = next((u for n, u in assets.items() if n.endswith(wanted)), "")
sums = assets.get("SHA256SUMS.txt", "")
print(d.get("tag_name", ""), pick, sums)
') || true
[ -n "$tag" ] || die "could not read the release tag from the API response"
[ -n "$asset_url" ] || die "release $tag has no $FORMAT asset for amd64"
echo "tag     $tag"
echo "asset   ${asset_url##*/}"
echo "into    $DL"

say "Download"
file="$DL/${asset_url##*/}"
[ -f "$file" ] || curl -fL --progress-bar -o "$file" "$asset_url" || die "download failed"
if [ -n "$sums_url" ]; then
  curl -fsSL -o "$DL/SHA256SUMS.txt" "$sums_url" || die "could not fetch SHA256SUMS.txt"
else
  die "release $tag has no SHA256SUMS.txt — refusing to install an unverified package"
fi

say "Verify"
( cd "$DL" && sha256sum -c SHA256SUMS.txt --ignore-missing ) | grep -E "OK$" \
  || die "checksum verification failed for ${file##*/}"
echo "sha256 verified against the release's own SHA256SUMS.txt"

if [ "$FORMAT" = "deb" ]; then
  say "Install (.deb)"
  pkg=$(dpkg-deb -f "$file" Package)
  # apt, not dpkg -i: it resolves the WebKitGTK 4.1 / GTK3 / appindicator / librsvg deps.
  sudo apt-get install -y "$file"
  ver=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || echo "?")
  bin=$(dpkg -L "$pkg" 2>/dev/null | grep -E '/(usr/)?bin/[^/]+$' | head -1 || true)
  echo "installed $pkg $ver"
  [ -n "$bin" ] && echo "binary    $bin"
else
  say "Install (AppImage)"
  # libfuse2 became libfuse2t64 in 24.04; try both, only if neither is present.
  if ! ldconfig -p | grep -q 'libfuse\.so\.2'; then
    sudo apt-get install -y libfuse2t64 2>/dev/null || sudo apt-get install -y libfuse2 \
      || echo "warn: no libfuse2 found; the AppImage may not start" >&2
  fi
  mkdir -p "$HOME/ai/bin"
  install -m 755 "$file" "$HOME/ai/bin/LU.AppImage"
  echo "installed $HOME/ai/bin/LU.AppImage"
fi

cat <<EOF

Next:
  1. A session is required (it is a desktop app): ./scripts/00-preflight.sh shows whether one exists.
  2. If Create will be used, stop the ai-box ComfyUI so both do not want :8188:
       sudo systemctl stop comfyui
  3. Start it inside the desktop session: ./scripts/90-launch.sh
  4. First run: let the wizard install the LU Engine, or point it at Ollama.
     Stop llama-server first if both would hold the model in GPU memory:
       sudo systemctl stop llama-server
EOF
