#!/usr/bin/env bash
# 90-launch.sh — start Locally Uncensored with a log you can read when the window misbehaves.
#
#   ./scripts/90-launch.sh                  # run in the foreground, log to ~/.local/state/lu-box
#   ./scripts/90-launch.sh --no-compositing # WEBKIT_DISABLE_COMPOSITING_MODE=1 (blank window fix)
#   ./scripts/90-launch.sh --detach         # background it and return
#
# Run this inside the desktop session (RDP or the box's console), not over a bare SSH shell.
set -euo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/lu-box"
LOG="$STATE/lu.log"
COMPOSITING=1
DETACH=0

die() { echo "error: $*" >&2; exit 1; }
say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

for a in "$@"; do
  case "$a" in
    --no-compositing) COMPOSITING=0 ;;
    --detach)         DETACH=1 ;;
    -h|--help)        sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)                die "unknown argument: $a (try --help)" ;;
  esac
done

say "Session"
if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  cat >&2 <<EOF
No graphical session in this shell (DISPLAY and WAYLAND_DISPLAY are both unset).
LU is a Tauri desktop app and cannot start without one.

  server install: sudo ./scripts/10-desktop-session.sh   then connect over RDP and run this there
  desktop install: log in at the box, open a terminal, run this again
EOF
  exit 1
fi
echo "DISPLAY=${DISPLAY:-} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"

say "Binary"
bin=""
if command -v locally-uncensored >/dev/null; then
  bin="$(command -v locally-uncensored)"
else
  pkg=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | grep -iE 'locally[-.]?uncensored|^lu$' | head -1 || true)
  if [ -n "$pkg" ]; then
    bin=$(dpkg -L "$pkg" 2>/dev/null | grep -E '/(usr/)?bin/[^/]+$' | head -1 || true)
  fi
fi
[ -n "$bin" ] && [ -x "$bin" ] || bin="$HOME/ai/bin/LU.AppImage"
[ -x "$bin" ] || die "LU is not installed (./scripts/20-install-lu.sh)"
echo "$bin"

# WebKitGTK on RADV can open a window with nothing in it. These are the two switches upstream
# ecosystems use; they are cheap and reversible, so the flag only sets them for this launch.
if [ "$COMPOSITING" -eq 0 ]; then
  export WEBKIT_DISABLE_COMPOSITING_MODE=1
  export WEBKIT_DISABLE_DMABUF_RENDERER=1
  echo "compositing disabled for this launch"
fi

mkdir -p "$STATE"
echo "log     $LOG"

if [ "$DETACH" -eq 1 ]; then
  setsid nohup "$bin" >>"$LOG" 2>&1 &
  sleep 3
  if kill -0 $! 2>/dev/null; then
    echo "started (pid $!). If no window appears: tail -n 40 $LOG"
  else
    echo "it exited immediately — last lines:" >&2
    tail -n 20 "$LOG" >&2
    exit 1
  fi
else
  echo "starting in the foreground; close the window or Ctrl+C to stop"
  # tee keeps the console useful and leaves the log behind for the next run.
  "$bin" 2>&1 | tee -a "$LOG"
  status=${PIPESTATUS[0]}
  if [ "$status" -ne 0 ]; then
    echo "LU exited with status $status — last lines:" >&2
    tail -n 20 "$LOG" >&2
    exit "$status"
  fi
fi
