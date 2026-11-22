#!/usr/bin/env bash
# 00-preflight.sh — read-only report for a Locally Uncensored install on the box.
# Nothing here changes state.
#
#   ./scripts/00-preflight.sh
set -uo pipefail

ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; }
bad()  { printf '  \033[31mfail\033[0m  %s\n' "$*"; }
info() { printf '  .....  %s\n' "$*"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$*"; }

port_busy() {
  # 0 when something is listening on the port, 1 when nothing is.
  (exec 3<>"/dev/tcp/127.0.0.1/$1") >/dev/null 2>&1 && { exec 3>&-; return 0; }
  return 1
}

head_ "Host"
printf '  kernel    %s\n' "$(uname -r)"
printf '  distro    %s\n' "$( (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") || echo unknown)"
printf '  arch      %s\n' "$(uname -m)"
printf '  memory    %s\n' "$(awk '/MemTotal/{printf "%.0f GiB total\n", $2/1048576}' /proc/meminfo 2>/dev/null || echo unknown)"
printf '  user      %s\n' "$(id -un)"

head_ "Graphical session"
if command -v systemctl >/dev/null && systemctl is-active --quiet display-manager 2>/dev/null; then
  ok "display-manager active ($(systemctl show -p Id --value display-manager 2>/dev/null))"
else
  warn "no display-manager running"
fi
if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  ok "this shell has a session (DISPLAY=${DISPLAY:-} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-})"
else
  warn "this shell has no DISPLAY/WAYLAND_DISPLAY — LU cannot start from here"
  info "over SSH that is expected: run it inside RDP/VNC, or from the box's monitor"
fi
if command -v systemctl >/dev/null && systemctl is-active --quiet xrdp 2>/dev/null; then
  ok "xrdp active (RDP on :3389)"
elif [ -n "$(dpkg-query -W -f='${Status}' xrdp 2>/dev/null | grep -o 'install ok installed' || true)" ]; then
  warn "xrdp installed but not running: sudo systemctl enable --now xrdp"
else
  info "no xrdp — ./scripts/10-desktop-session.sh adds XFCE + xrdp"
fi
[ -d /usr/share/xsessions ] && info "sessions: $(ls /usr/share/xsessions 2>/dev/null | tr '\n' ' ')"

head_ "WebKitGTK / GTK (what a Tauri window needs)"
for lib in libwebkit2gtk-4.1.so.0 libgtk-3.so.0 libayatana-appindicator3.so.1 librsvg-2.so.2; do
  if ldconfig -p 2>/dev/null | grep -q "$lib"; then
    ok "$lib"
  else
    warn "$lib missing (apt-get install -y runs as part of 20-install-lu.sh)"
  fi
done

head_ "Vulkan (the engine's backend on gfx1151)"
if [ -e /dev/dri/renderD128 ]; then
  ok "render node $(ls /dev/dri/renderD128 2>/dev/null)"
else
  warn "no /dev/dri/renderD128 — the iGPU did not come up"
fi
if id -nG "$(id -un)" | tr ' ' '\n' | grep -qxE 'render|video'; then
  ok "$(id -un) is in render/video"
else
  warn "$(id -un) not in render/video: sudo usermod -aG render,video $(id -un)"
fi
if command -v vulkaninfo >/dev/null; then
  dev=$(vulkaninfo --summary 2>/dev/null | grep -m1 -i 'deviceName' | sed 's/.*= *//')
  [ -n "$dev" ] && ok "Vulkan device: $dev" || warn "vulkaninfo found no device — sudo ./scripts/30-vulkan-engine.sh"
else
  info "vulkaninfo not installed (sudo ./scripts/30-vulkan-engine.sh)"
fi

head_ "Locally Uncensored"
lu_bin=""
pkg=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | grep -iE 'locally[-.]?uncensored|^lu$' | head -1 || true)
if [ -n "$pkg" ]; then
  ver=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null)
  ok "package $pkg $ver"
  lu_bin=$(dpkg -L "$pkg" 2>/dev/null | grep -E '/(usr/)?bin/[^/]+$' | head -1 || true)
  [ -n "$lu_bin" ] && info "binary $lu_bin" || warn "no binary found in $pkg"
else
  info "LU is not installed yet (./scripts/20-install-lu.sh)"
fi
if [ -x "$HOME/ai/bin/LU.AppImage" ]; then
  ok "AppImage present: $HOME/ai/bin/LU.AppImage"
fi

head_ "Engines"
if command -v ollama >/dev/null; then
  ok "ollama $(ollama --version 2>/dev/null | sed 's/^ollama version is //')"
  port_busy 11434 && info "ollama API answering on :11434" || warn "ollama installed but :11434 is not listening"
else
  info "no ollama (optional: ./scripts/30-vulkan-engine.sh --ollama)"
fi
if [ -x "$HOME/ai/llama.cpp/build/bin/llama-server" ] || [ -x "$HOME/ai/llama.cpp/build-vulkan/bin/llama-server" ]; then
  ok "ai-box llama-server build present"
fi
for p in 8080 1234 11434; do
  port_busy "$p" && info "port $p is in use" || true
done

head_ "Ports LU will use"
for p in 8129 11435 8188; do
  if port_busy "$p"; then
    case "$p" in
      8188) warn ":$p busy — that is ai-box ComfyUI. LU's Create tab installs its own; sudo systemctl stop comfyui" ;;
      *)    warn ":$p busy — LU wants this one (8129 local API, 11435 Remote tab)" ;;
    esac
  else
    ok ":$p free"
  fi
done

head_ "GPU memory budget"
if [ -r /sys/module/ttm/parameters/pages_limit ]; then
  pl=$(cat /sys/module/ttm/parameters/pages_limit)
  awk -v p="$pl" 'BEGIN { printf "  .....  ttm.pages_limit=%s (~%.1f GiB GPU-addressable)\n", p, p*4096/1073741824 }'
else
  info "ttm parameters not readable (ai-box/scripts/10-gpu-memory.sh sets them)"
fi

head_ "Unprivileged user namespaces (Ubuntu 24.04+ hardening)"
if [ -r /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]; then
  u=$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns)
  if [ "$u" = "1" ]; then
    warn "restricted (=1) — WebKitGTK's bwrap sandbox can fail; see 40-fix-userns.sh if the log says so"
  else
    ok "not restricted (=0)"
  fi
else
  info "setting not present on this kernel"
fi

head_ "Disk"
df -h "$HOME" 2>/dev/null | tail -1 | awk '{printf "  .....  %s avail on %s\n", $4, $6}'
printf '\n'
