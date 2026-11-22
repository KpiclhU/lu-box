# lu-box — Locally Uncensored on a fresh Ubuntu box

Installing [Locally Uncensored](https://github.com/PurpleDoubleD/locally-uncensored) (LU) on a
clean Ubuntu install. The reference machine is a Framework Desktop — Ryzen AI Max+ 395, 64 GB,
Radeon 8060S (`gfx1151`), Ubuntu 26.04 — but nothing here depends on that beyond the driver note
in section 2.

LU is a **Tauri desktop app with a window**, and the box is headless, so installing it means
adding the one thing a Server install leaves out: a graphical session. Upstream says the same in
its FAQ:

> LU is a desktop app with a window, so it needs a graphical session: a desktop on the server, or
> one you reach over VNC or RDP. There is no `--host` flag.

So this repo is: a small XFCE + xrdp session, LU installed from the official `.deb`, a Vulkan
check for the engine, and a launcher that leaves you a log when the window does not appear.
Everything else — models, ComfyUI, the wizard that picks an engine — is LU's own job.

Because the box is fresh, nothing has to be negotiated at install time: no other engine is
holding GPU memory, no other process owns `:8188`, and there is no existing model store to link.
LU takes the machine as it finds it.

---

## 1. What LU runs, and on which ports

| Piece | Port | Notes |
|---|---|---|
| Chat engine (LU Engine, Vulkan/RADV) | none by default | Installed by the welcome wizard; it manages its own server process |
| Local API | `127.0.0.1:8129`, opt-in | Token protected. Off until you turn it on |
| Create tab (ComfyUI) | `:8188` | LU installs, starts and updates its own ComfyUI here — nothing exists on a fresh box |
| Remote tab | `:11435`, off by default | Full LU window from a phone: LAN or a Cloudflare tunnel, paired by QR code |
| Ollama, if you point LU at it | `127.0.0.1:11434` | Optional alternative engine (`30-vulkan-engine.sh --ollama`) |

Nothing in this repo installs a second copy of anything LU already ships, and nothing runs as a
system service of its own. `00-preflight.sh` checks all five ports so you can see what is taken
before you start.

## 2. Requirements

- Ubuntu 22.04 / 24.04 / 26.04, **amd64**. RPM distros work too, but these scripts are `apt` +
  `dpkg` throughout.
- A working Vulkan driver for the iGPU. `30-vulkan-engine.sh` installs `mesa-vulkan-drivers`,
  which is the RADV driver LU's engine uses on `gfx1151`.
- 8 GB RAM for chat, more for images. On 64 GB the constraint is GPU-addressable memory, not RAM.
- ~20 GB of disk for the app plus a model or two.
- A graphical session — added by `10-desktop-session.sh` if the install has none — **or** a
  monitor on the box with a desktop already installed.

## 3. Install

Run on the box, as your normal user, from this directory:

```bash
sudo ./scripts/10-desktop-session.sh      # XFCE + xrdp; exits early if a session already exists
./scripts/30-vulkan-engine.sh             # verify RADV sees the iGPU; install drivers if not
./scripts/20-install-lu.sh                # latest .deb from GitHub Releases, checksum verified
./scripts/90-launch.sh                    # start it inside the desktop session
```

Then connect and use it:

- **From your laptop:** RDP to `<box-hostname>.local:3389` (Remmina, Windows Remote Desktop,
  Microsoft Remote Desktop for Mac), log in as your user, and LU is on the desktop.
- **From the box's own monitor:** log in at the console; XFCE is the session.

`./scripts/00-preflight.sh` is read-only and safe to run at any point — before the install, after
it, and when something is broken.

### Package format

Use the `.deb`. The AppImage is offered first upstream, but on Ubuntu 24.04 and later it is the
worse path: it needs `libfuse2` (not installed by default) and it cannot carry the AppArmor
profile that unprivileged user namespaces now require on those releases, which is exactly what
WebKitGTK's web-process sandbox uses. `20-install-lu.sh --appimage` still exists if you want it;
it drops the executable in `~/.local/bin/LU.AppImage`.

### Pinning a version

```bash
./scripts/20-install-lu.sh --version v3.1.2
```

Without `--version` the script asks the GitHub API for the latest release, downloads
`Locally.Uncensored_<ver>_amd64.deb` plus `SHA256SUMS.txt` into
`~/.local/share/lu-box/downloads`, verifies the hash, and installs it with `apt` so the runtime
libraries (WebKitGTK 4.1, GTK 3, the appindicator, librsvg) resolve from the archive. Re-running
it upgrades in place; LU also has its own signed auto-update channel in **Settings → Updates**,
which is the normal way to stay current after the first install.

## 4. First run

1. The welcome wizard looks for an engine.
   - **Let it install the LU Engine** — simplest, uses Vulkan/RADV, and it is the path upstream
     tests on Linux.
   - **Or point it at Ollama** if you prefer one.
     `./scripts/30-vulkan-engine.sh --ollama` installs Ollama and pulls a small model.
2. **Models → download.** The manager marks what fits the hardware. On 64 GB with ~48 GiB
   GPU-addressable, these are the sensible first picks (from the upstream README):

   | Model | Size | Why |
   |---|---|---|
   | Llama 3.1 8B Abliterated | 5 GB | Fast first download, proves the stack |
   | Hermes 3 Llama 3.1 8B | 5 GB | Native tool calling, for the agent tab |
   | Qwen3-VL 8B Abliterated | 5 GB | Image understanding, small footprint |
   | Gemma 4 12B Heretic | 7.4 GB | A different voice; `IQ4_XS` for 8 GB cards |
   | Qwen 3.8 27B Uncensored | 18 GB (`IQ2_M` 11 GB) | The big one. ~19 tok/s with MTP on this class of box |

3. **Create** installs and starts its own ComfyUI on `:8188`. On a fresh box there is nothing to
   stop first — just use it.
4. **Remote** (optional): Settings → Voice & Remote. LAN or Cloudflare tunnel, paired by QR code
   and passcode, off by default. The full window is served on `:11435`.

## 5. When the window does not appear

Symptom → cause → fix, in the order worth checking. `./scripts/90-launch.sh` prints the log path
(`~/.local/state/lu-box/lu.log`) — read it before changing anything.

| Symptom | Likely cause | Fix |
|---|---|---|
| `cannot open display` / exits immediately | No session: this is a Server install and you are on SSH | `sudo ./scripts/10-desktop-session.sh`, then `90-launch.sh` from inside RDP |
| Window appears, page is blank | WebKitGTK compositing on RADV | `./scripts/90-launch.sh --no-compositing` (sets `WEBKIT_DISABLE_COMPOSITING_MODE=1`) |
| Crashes with a sandbox / `bwrap` error in the log | Ubuntu 24.04+ blocks unprivileged user namespaces for unconfined binaries | `sudo ./scripts/40-fix-userns.sh` — writes an AppArmor profile **for the LU binary only** (never disables the setting globally) |
| Install aborts on missing libraries | `dpkg -i` was used instead of `apt` | `sudo apt-get -f install`, then re-run `20-install-lu.sh` |
| Chat loads a model then stalls at 0 tok/s | The engine is not the one you expect, or a stale engine process still holds the GPU | Check what is running (`ss -ltnp`, `amdgpu_top`), close the other engine, restart LU |
| Create tab cannot start ComfyUI | Something else is already listening on `:8188` | `ss -ltnp '( sport = :8188 )'`, stop that process, retry in LU |

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
  **not** been run on the box: this repo was authored off-box, with no SSH session to it. Treat
  the first run of each script as a supervised run.
- `10-desktop-session.sh` installs XFCE + xrdp because that is the smallest session that runs a
  WebKitGTK app. A full Ubuntu Desktop install works identically and needs no script.
- The `bwrap`/AppArmor row is the documented behaviour of Ubuntu 24.04+ for unconfined binaries;
  whether LU's WebKit build trips it on this exact Mesa/Ubuntu pair is untested here. If the log
  does not mention a sandbox error, do not run `40-fix-userns.sh`.
- Upstream has no independent security audit yet, and the Windows installer is unsigned. The
  `.deb` here is verified by SHA-256 against the release's own `SHA256SUMS.txt`; the auto-update
  channel afterwards is minisign-signed against a published key.
