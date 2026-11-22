#!/usr/bin/env bash
# 10-desktop-session.sh — give a headless Ubuntu install a session a Tauri app can use.
#
#   sudo ./scripts/10-desktop-session.sh
#
# Installs XFCE (small: ~400 MB) plus xrdp, so you can reach the desktop with any RDP client.
# Idempotent: re-running it only fills in what is missing, and it installs nothing LU ships itself.
set -euo pipefail

SESSION_USER="${SESSION_USER:-${SUDO_USER:-}}"

die() { echo "error: $*" >&2; exit 1; }
say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

[ "$(id -u)" -eq 0 ] || die "run with sudo: sudo ./scripts/10-desktop-session.sh"
[ -n "$SESSION_USER" ] && [ "$SESSION_USER" != "root" ] \
  || die "cannot tell which user owns the session; run: sudo SESSION_USER=<user> ./scripts/10-desktop-session.sh"

command -v apt-get >/dev/null || die "this script is for Debian/Ubuntu (apt-get not found)"
command -v systemctl >/dev/null || die "systemd not found"

say "Current state"
if systemctl is-active --quiet display-manager; then
  echo "a display-manager is already running: nothing to install."
  echo "log in at the console, or install an RDP server of your choice if you need remote access."
  exit 0
fi
echo "no display-manager yet — installing XFCE + xrdp for user '$SESSION_USER'"

say "Packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  xfce4 xfce4-terminal xfce4-goodies dbus-x11 \
  xorgxrdp xrdp \
  mesa-utils

say "xrdp"
# xrdp reads the TLS key through the ssl-cert group; without this it starts and refuses logins.
adduser xrdp ssl-cert >/dev/null 2>&1 || true
# The RDP session must reach the iGPU for WebKitGTK to composite.
usermod -aG render,video "$SESSION_USER" || true

# xrdp's startwm.sh sources ~/.xsession when it exists; keep ours minimal and per-user.
xsession="/home/$SESSION_USER/.xsession"
if [ ! -f "$xsession" ]; then
  printf '#!/bin/sh\n# Added by lu-box/10-desktop-session.sh — xrdp hands off to XFCE here.\nexec startxfce4\n' > "$xsession"
  chmod 755 "$xsession"
  chown "$SESSION_USER":"$SESSION_USER" "$xsession"
  echo "wrote $xsession"
else
  echo "kept existing $xsession"
fi

say "Enable"
systemctl enable --now xrdp
systemctl --quiet is-active xrdp && echo "xrdp is running" || die "xrdp failed to start: journalctl -u xrdp -n 50"

if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q 'Status: active'; then
  ufw allow 3389/tcp >/dev/null && echo "ufw: allowed 3389/tcp"
fi

ip=$(hostname -I 2>/dev/null | awk '{print $1}')
cat <<EOF

Ready.
  RDP to  ${ip:-<box-ip>}:3389  as  $SESSION_USER   (Remmina, Windows Remote Desktop, etc.)
  Or log in at the box's own monitor; XFCE is now the session.

  Next: ./scripts/30-vulkan-engine.sh  and  ./scripts/20-install-lu.sh
  Then start LU from inside the RDP session: ./scripts/90-launch.sh

  'render'/'video' group changes apply to the next login, not the session you are in.
EOF
