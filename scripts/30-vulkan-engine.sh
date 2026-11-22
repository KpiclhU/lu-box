#!/usr/bin/env bash
# 30-vulkan-engine.sh — make sure the iGPU is usable as a Vulkan device for the LU Engine.
#
#   ./scripts/30-vulkan-engine.sh              # check, install the RADV driver if missing
#   ./scripts/30-vulkan-engine.sh --ollama     # also install Ollama as a fallback engine
#
# LU's own engine is a Vulkan build on Linux. On gfx1151 that is Mesa's RADV; there is no ROCm
# or HSA_OVERRIDE_GFX_VERSION involved, unlike the llama.cpp/ComfyUI path in the ai-box repo.
set -euo pipefail

OLLAMA=0
for a in "$@"; do
  case "$a" in
    --ollama) OLLAMA=1 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "error: unknown argument: $a" >&2; exit 1 ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }
say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

say "Driver"
if ! command -v vulkaninfo >/dev/null; then
  echo "vulkaninfo missing — installing Mesa RADV and the Vulkan loader"
  sudo apt-get update
  sudo apt-get install -y mesa-vulkan-drivers libvulkan1 vulkan-tools
fi
if ! ldconfig -p | grep -q 'libvulkan\.so\.1'; then
  sudo apt-get install -y libvulkan1
fi

say "Device"
# vulkaninfo works without a display for enumeration; only the surface extensions need one.
summary=$(vulkaninfo --summary 2>&1 || true)
dev=$(printf '%s\n' "$summary" | grep -m1 -i 'deviceName' | sed 's/.*= *//')
if [ -z "$dev" ]; then
  printf '%s\n' "$summary" | tail -5 >&2
  die "no Vulkan device. Check /dev/dri/renderD128 and that linux-firmware is current; on this box the driver is amdgpu + RADV."
fi
echo "device  $dev"
printf '%s\n' "$summary" | grep -iE 'driverName|apiVersion|driverInfo' | sed 's/^/        /'
case "$dev" in
  *8060S*|*Radeon*|*AMD*) echo "ok: AMD iGPU visible to Vulkan" ;;
  *) echo "warn: that is not the 8060S — if it is llvmpipe, the RADV driver is not being picked up" >&2 ;;
esac

if id -nG "$(id -un)" | tr ' ' '\n' | grep -qxE 'render|video'; then
  echo "ok: $(id -un) is in render/video"
else
  echo "adding $(id -un) to render,video (log out and back in for it to apply)"
  sudo usermod -aG render,video "$(id -un)"
fi

if [ "$OLLAMA" -eq 1 ]; then
  say "Ollama (optional fallback engine)"
  if command -v ollama >/dev/null; then
    echo "already installed: $(ollama --version 2>/dev/null || echo unknown version)"
  else
    tmp=$(mktemp) && curl -fsSL -o "$tmp" https://ollama.com/install.sh \
      || die "could not download the Ollama installer"
    sh "$tmp"
    rm -f "$tmp"
  fi
  systemctl is-enabled --quiet ollama 2>/dev/null || sudo systemctl enable --now ollama
  if ! ollama list 2>/dev/null | grep -qiE 'llama3|qwen|gemma'; then
    echo "pulling llama3.1:8b as a small first model (~5 GB)"
    ollama pull llama3.1:8b || echo "warn: pull failed; LU can still see the engine" >&2
  fi
  echo "Ollama API: http://127.0.0.1:11434"
fi

cat <<EOF

Next:
  ./scripts/20-install-lu.sh
  ./scripts/90-launch.sh        # from inside the desktop session, not over bare SSH

  If chat is slow or the model lands on the processor, check whether ai-box's llama-server is
  holding the GPU memory: sudo systemctl stop llama-server
EOF
