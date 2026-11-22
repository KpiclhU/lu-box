# lu-box — Locally Uncensored on the ai-box

Installing [Locally Uncensored](https://github.com/PurpleDoubleD/locally-uncensored) (LU) on the
Framework Desktop: Ryzen AI Max+ 395, 64 GB, Radeon 8060S (`gfx1151`), Ubuntu 26.04.

The sibling `ai-box` repo builds that machine as a **headless** box: llama-server, ComfyUI and a
bot, all HTTP on loopback. LU is the opposite kind of program — a **Tauri desktop app with a
window** — so installing it here means adding the one thing the box deliberately left out: a
graphical session. Upstream says the same thing in its FAQ:

> LU is a desktop app with a window, so it needs a graphical session: a desktop on the server, or
> one you reach over VNC or RDP. There is no `--host` flag.

So this repo is: a small XFCE + xrdp session on the box, LU installed from the official `.deb`,
a Vulkan check for the engine, and a launcher that gives you a log when the window does not
appear. Everything else (models, ComfyUI, the wizard that picks an engine) is LU's own job.

---

## 1. What LU brings, and what it collides with

| | LU does | The box already has | What to do |
|---|---|---|---|
| Chat | Its own LU Engine (Vulkan) or an engine it detects: Ollama, LM Studio, llama.cpp, vLLM, … | `llama-server` on `127.0.0.1:8080` | Pick one at a time. Two engines both want ~20–40 GB of the 48 GiB GPU budget |
| Images/video | Installs and runs its **own ComfyUI** | `comfyui.service` on `:8188` | `sudo systemctl stop comfyui` while LU's Create tab manages its own |
| Model files | Downloads into its own store, can *link* models another tool already has | `~/ai/models/*.gguf` | Link, don't copy — LU can reference existing GGUFs |
| Local API | `:8129`, opt-in, token required | `:8080/v1` | Both can coexist; they are different ports |
| Remote tab | Full LU window from a phone, LAN or Cloudflare tunnel on `:11435`, off by default | OpenClaw on `:18789` | Independent. Leave LU's remote off until you want it |

Nothing in this repo touches the `ai-box` units. The only real conflicts are **VRAM** and **port
8188**, and both are switches you flip, not installs you undo.

## 2. Requirements

- Ubuntu 22.04 / 24.04 / 26.04, **amd64**. (RPM-based distros work too, but the scripts here are
  `apt` + `dpkg`.)
- A working Vulkan driver for the iGPU. `ai-box/scripts/00-preflight.sh` already installs
  `mesa-vulkan-drivers`, which is the RADV driver LU's engine uses on `gfx1151`.
- 8 GB RAM for chat, more for images — this box has 64 GB, so it is not the constraint.
- A graphical session (added by `10-desktop-session.sh`) **or** a monitor on the box with a
  desktop already installed.

## 3. Install

Run on the box, as your normal user (`ai`), from this directory:

```bash
sudo ./scripts/10-desktop-session.sh      # XFCE + xrdp, only if the box has no session yet
./scripts/30-vulkan-engine.sh             # verify RADV sees the 8060S; install drivers if not
./scripts/20-install-lu.sh                # latest .deb from GitHub Releases, checksum verified
./scripts/90-launch.sh                    # start it inside the desktop session
```

Then connect and use it:

- **From your laptop:** RDP to `ai-box.local:3389` (Remmina, Windows Remote Desktop, Microsoft
  Remote Desktop for Mac), log in as `ai`, and LU is on the desktop.
- **From the box's own monitor:** log in at the console; XFCE is the session.

`./scripts/00-preflight.sh` is read-only and safe to run at any point — before the install, after
it, and when something is broken.

### Package format

Use the `.deb`. The AppImage is offered first upstream, but on Ubuntu 24.04 and later it is the
worse path on this box: it needs `libfuse2` (not installed by default) and it cannot carry the
AppArmor profile that unprivileged user namespaces now require on these releases, which is
exactly what WebKitGTK's web-process sandbox uses. `20-install-lu.sh --appimage` still exists if
you want it.

### Pinning a version

```bash
./scripts/20-install-lu.sh --version v3.1.2
```

Without `--version` the script asks the GitHub API for the latest release, downloads
`Locally.Uncensored_<ver>_amd64.deb` plus `SHA256SUMS.txt`, verifies the hash, and installs it
with `apt` so the runtime libraries (WebKitGTK 4.1, GTK 3, the appindicator, librsvg) resolve
from the archive. Re-running it upgrades in place; LU also has its own signed auto-update
channel in **Settings → Updates**, which is the normal way to stay current after the first
install.

## 4. First run

1. The welcome wizard looks for an engine. On this box:
   - **Let it install the LU Engine** — simplest, uses Vulkan/RADV, and it is the path upstream
     tests on Linux. Stop `llama-server` first if both would fight over memory.
   - **Or point it at Ollama** if you already run one. `./scripts/30-vulkan-engine.sh --ollama`
     installs Ollama and pulls a small model as a fallback engine.
2. **Models → download.** The manager marks what fits the hardware. On 64 GB with ~48 GiB
   GPU-addressable, these are the sensible first picks (from the upstream README):

   | Model | Size | Why |
   |---|---|---|
   | Llama 3.1 8B Abliterated | 5 GB | Fast first download, proves the stack |
   | Hermes 3 Llama 3.1 8B | 5 GB | Native tool calling, for the agent tab |
   | Qwen3-VL 8B Abliterated | 5 GB | Image understanding on an 8 GB card |
   | Gemma 4 12B Heretic | 7.4 GB | A different voice; `IQ4_XS` for 8 GB cards |
   | Qwen 3.8 27B Uncensored | 18 GB (`IQ2_M` 11 GB) | The big one. ~19 tok/s with MTP on this class of box |

3. **Create** wants a ComfyUI. Stop the `ai-box` one first so they do not fight over `:8188`:
   ```bash
   sudo systemctl stop comfyui
   ```
   LU installs, starts, repairs and updates its own copy. `sudo systemctl disable comfyui` if you
   never want the old one back.
4. **Remote** (optional): Settings → Voice & Remote. LAN or Cloudflare tunnel, paired by QR code
   and passcode, off by default. The full window is on `:11435`.

## 5. When the window does not appear

Symptom → cause → fix, in the order worth checking. `./scripts/90-launch.sh` prints the log path
(`~/.local/state/lu-box/lu.log`) — read it before changing anything.

| Symptom | Likely cause | Fix |
|---|---|---|
| `cannot open display` / exits immediately | No session: this is a Server install and you are on SSH | `sudo ./scripts/10-desktop-session.sh`, then `90-launch.sh` from inside RDP |
| Window appears, page is blank | WebKitGTK compositing on RADV | `./scripts/90-launch.sh --no-compositing` (sets `WEBKIT_DISABLE_COMPOSITING_MODE=1`) |
| Crashes with a sandbox / `bwrap` error in the log | Ubuntu 24.04+ blocks unprivileged user namespaces for unconfined binaries | `sudo ./scripts/40-fix-userns.sh` — writes an AppArmor profile **for the LU binary only** (never disables the setting globally) |
| Install aborts on missing libraries | `dpkg -i` was used instead of `apt` | `sudo apt-get -f install`, then re-run `20-install-lu.sh` |
| Chat loads a model then stalls at 0 tok/s | `llama-server` still holds the GPU memory | `sudo systemctl stop llama-server` |
| Create tab cannot start ComfyUI | `ai-box` ComfyUI owns `:8188` | `sudo systemctl stop comfyui` |

## 6. Repo layout

```
README.md                     this page
scripts/
  00-preflight.sh             read-only report: session, WebKitGTK, Vulkan, ports, LU version
  10-desktop-session.sh       XFCE + xrdp on a headless Server install (idempotent)
  20-install-lu.sh            latest .deb from GitHub Releases, SHA-256 verified, apt-installed
  30-vulkan-engine.sh         RADV/Vulkan check for the LU Engine; --ollama for a fallback engine
  40-fix-userns.sh            scoped AppArmor userns profile for the LU binary (opt-in)
  90-launch.sh                start LU with a log; --no-compositing, --detach
.gitignore                    downloaded packages and logs
```

## 7. Honest status

- Written against upstream **v3.1.2** (19 November 2026) and the assets that release actually
  publishes: `Locally.Uncensored_3.1.2_amd64.deb`, `.AppImage`, `.rpm`, `SHA256SUMS.txt`.
- The scripts are syntax-checked (`bash -n`) on the machine this repo was written on. They have
  **not** been run against the box: this repo was authored off-box, with no SSH session to it.
  Treat the first run of each script as a supervised run.
- `10-desktop-session.sh` installs XFCE + xrdp because that is the smallest session that runs a
  WebKitGTK app. A full Ubuntu Desktop install works identically and needs no script.
- The `bwrap`/AppArmor row is the documented behaviour of Ubuntu 24.04+ for unconfined binaries;
  whether LU's WebKit build trips it on this exact Mesa/Ubuntu pair is untested here. If the log
  does not mention a sandbox error, do not run `40-fix-userns.sh`.
- Upstream has no independent security audit yet, and the Windows installer is unsigned. The
  `.deb` here is verified by SHA-256 against the release's own `SHA256SUMS.txt`; the auto-update
  channel afterwards is minisign-signed against a published key.
