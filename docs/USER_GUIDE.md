# User Guide

Everything a user needs: installing the APK, the first run, what each tab does, how to use every
tool, and what to do when something goes wrong.

> **Status of this release.** CI builds the APK, but **the runtime has not been verified on a
> physical device yet**. Expect rough edges around the first-run download and around starting the
> services; please report them in
> [Issues](https://github.com/Allsungood/termux-dsh-allinone/issues).

**Contents**

- [What you need](#what-you-need)
- [Install the APK](#install-the-apk)
- [First run](#first-run)
- [The Tools tab](#the-tools-tab)
- [The Console tab](#the-console-tab)
- [The Settings tab](#the-settings-tab)
- [Tool by tool](#tool-by-tool)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [Quick command reference](#quick-command-reference)

---

## What you need

| | |
|---|---|
| Android | 7.0 (API 24) or newer |
| CPU | **arm64 (aarch64)** or **x86_64** only. 32-bit ARM devices are not supported at all. |
| Free storage | ~55 MB of downloads on first run plus the unpacked rootfs and packages — plan for a few GB. Ollama adds ~1.5 GB before any model. |
| Network | Wi-Fi strongly recommended. The installer reaches GitHub, `cdimage.ubuntu.com`, `nodejs.org`, the Ubuntu archive and npm. |
| Root | Not required — and not used. |

Not sure which APK you need? Every mainstream Android phone and tablet since roughly 2017 is
**arm64**. Emulators and x86 Chromebooks need **x86_64**.

---

## Install the APK

1. Open [GitHub Releases](https://github.com/Allsungood/termux-dsh-allinone/releases/latest).
2. Download `termux-allinone-arm64.apk` or `termux-allinone-x86_64.apk`.
3. Allow your browser or file manager to install unknown apps, then tap the downloaded file and
   install it.
4. You will see a warning about installing an app from outside a store — that is expected, this app
   is **not on Google Play** (see [Why targetSdk 28](../README.md#why-targetsdk-28)).
5. Launch **Termux All-in-One**.

The app displays as *Termux All-in-One*; its package is `com.allsungood.termux_dsh_allinone`.

---

## First run

The first screen explains what is about to be installed and offers one button: **Install
environment**.

1. Tap it. A progress bar and a live log console appear.
2. The installer works through six phases: PRoot → Ubuntu rootfs → base packages (`git`, `python3`,
   `curl`, `ca-certificates`, `xz-utils`, `tar`, `bash`, `ripgrep`, `procps`) → Node.js 22.11.0 →
   `npm install -g @deepseek-ai/dsh openclaw` → verification.
3. On a fast Wi-Fi connection the ~55 MB of downloads take a few minutes; the apt and npm steps add
   more time and are CPU-bound. **Keep the screen on and the app in the foreground.**
4. When it says *Setup complete*, tap **Open dashboard**.

Things you may see in the log:

| Log line | Meaning |
|---|---|
| `WARNING: npm global install exited with code …` | dsh/OpenClaw could not be installed from npm. **Not fatal** — retry later from the Console with `npm install -g @deepseek-ai/dsh openclaw`. |
| `ERROR: FormatException: Unsupported CPU architecture…` | Your device is neither arm64 nor x86_64. There is no build for it. |
| `ERROR: HttpException: HTTP 404 while fetching …` | An upstream URL moved. Please open an issue. |
| `Setup failed` + an error line | The button becomes **Retry installation**; retry is cheap because already-downloaded archives are reused. |

If the download is interrupted (screen off, app killed, network drop), a **partial file** may be left
in the download cache. Retries reuse it and then fail at extraction. Delete it from the Console and
retry:

```sh
ls -l /host-downloads
rm /host-downloads/ubuntu-base-24.04.5-base-arm64.tar.gz     # or whichever file is truncated
```

---

## The Tools tab

The dashboard. Each tool gets a card showing a state and the actions that make sense for it.

| Card state | Meaning |
|---|---|
| `running` (green dot) | The app has a live process for it. |
| `installed` | The binary exists inside the guest, but no process is running. |
| `not installed` | Absent, and it is optional (currently only Ollama). |
| `missing` | Absent, and the installer should have put it there — try Settings → **Repair / re-run installation**. |

Buttons:

| Button | What it does |
|---|---|
| **Start** | Runs the tool's service as a background guest process: `dsh web --port 3080 --host 127.0.0.1`, `openclaw gateway`, or `ollama serve`. |
| **Stop** | Sends `SIGTERM` to that process. |
| **Open** | Opens the tool's local dashboard in an in-app WebView (dsh on `http://127.0.0.1:3080`, OpenClaw on `http://127.0.0.1:18789`). |
| **Install** | Ollama only: runs the ~1.5 GB install on a progress-and-log screen. |

The summary card at the top counts how many of the six catalogue entries are ready. Pull down to
re-probe — the app answers "what is installed?" with a single PRoot invocation that checks `node`,
`npm`, `git`, `python3`, `dsh`, `openclaw` and `ollama` inside the guest.

**Start the services here, not in the Console.** The Tools tab keeps their output visible (the last
400 lines per tool) and gives you a Stop button; a foreground command typed into the Console has
neither.

---

## The Console tab

A shell running **inside the guest** (`/bin/sh` under PRoot), with a row of quick-command chips:
`dsh --version`, `dsh web --port 3080`, `openclaw gateway`, `ollama list`, `node --version`,
`python3 --version`. Type a command, press the send button (or the keyboard's send action) and the
output appears above, colour-coded.

What works well: ordinary line-oriented commands, `apt-get install`, `git`, `npm`, `python3`,
`curl`, `rg`, `ls`, `cat`, `df`, `du`, `ps`, `free`.

What does **not** work, by design:

- **It is a pipe, not a PTY.** Full-screen curses programs — `vi`, `nano`, `htop`, `top` — cannot
  render. Use `cat`/`sed` to edit files, and `ps`/`free` for status.
- **No job control and no way to send Ctrl-C** from the UI. Do not start a long-running foreground
  server in the Console; start it from the Tools tab instead.
- **No Tab completion and no arrow-key history.** The input is a normal text field; you can select
  and copy output text, but the shell never sees keystrokes other than whole lines you submit.

Useful facts: `HOME` is `/root`, the working directory is `/root`, `PATH` includes `/usr/local/bin`,
and the file cache from the installer is mounted read-write at `/host-downloads`. The guest cannot
see your phone's shared storage (`/sdcard` is not mounted).

---

## The Settings tab

| Setting | Default | Notes |
|---|---|---|
| dsh web UI port | `3080` | Validated as an integer between 1 and 65535. |
| OpenClaw gateway port | `18789` | Same validation. |
| Ollama port | `11434` | Same validation. |
| Default Ollama model | `llama3.2:1b` | Must be non-empty. |
| Keep services awake | on | See the caveat below. |
| **Repair / re-run installation** | — | Re-runs the full installer on a progress-and-log screen. |

**Two honest caveats about this tab:**

1. The port/keep-awake values are **stored preferences**. The Tools tab starts the services with its
   built-in commands (`dsh web --port 3080 --host 127.0.0.1`, `openclaw gateway`, `ollama serve`)
   and the Open buttons point at the default URLs. If you change a port here, launch the service
   manually from the Console with a matching flag, for example
   `dsh web --port 8080 --host 127.0.0.1`.
2. There is currently **no foreground service or wake-lock implementation** in the app, so the
   "keep services awake" switch does not by itself keep Android from reclaiming the processes. See
   [Background kills](#background-kills).

**Repair** re-runs the installer without wiping anything: PRoot is re-extracted and re-`chmod`ed, the
package step and the `npm install -g` step run again, and cached archives are reused. It does **not**
re-extract the Ubuntu rootfs while `rootfs/etc/os-release` exists, so it cannot upgrade the Ubuntu
version in place. For a genuinely clean install, clear the app's data from Android's app settings
(Settings → Apps → Termux All-in-One → Storage → **Clear data**); the next launch returns to the
setup screen.

---

## Tool by tool

### dsh (DeepSeek Harness)

An AI coding agent with a web UI.

1. **Tools** tab → **dsh** card → **Start**. The app runs
   `dsh web --port 3080 --host 127.0.0.1` inside the guest.
2. Tap **Open** to load `http://127.0.0.1:3080` in the in-app WebView, or open it in your normal
   browser with the ↗ button.

The installer pre-seeds the config so the launcher never stalls on a confirmation prompt:

```
/root/.dsh/config.json  →  {"approvalPolicy":"never","webPort":3080}
```

Read it or change it from the Console:

```sh
cat /root/.dsh/config.json
dsh --version
```

### OpenClaw

An AI gateway that runs in the guest as a Node.js service.

1. **Tools** tab → **OpenClaw** card → **Start** (runs `openclaw gateway`).
2. **Open** loads `http://127.0.0.1:18789`.

If the service exits immediately, its output is in the card's log — open the Tools tab again and
check the last lines before it stopped.

### Ollama (optional, ~1.5 GB)

Ollama is **never** installed by the default setup; you trigger it yourself.

1. **Tools** tab → **Ollama** card → **Install**. Stay on Wi-Fi and keep the screen on: the archive
   is about 1.5 GB, and it is unpacked inside the guest with `tar --zstd` (Android's own `tar` has no
   zstd support, so `zstd` is installed from the Ubuntu archive first).
2. When it finishes, tap **Start** on the Ollama card — that runs `ollama serve` (port 11434).
3. Pull and run a model **from the Console**:

```sh
ollama pull llama3.2:1b      # small model, a good first choice
ollama list
ollama run llama3.2:1b
```

Reality check: **a model may not fit in your device's RAM.** If the app or the guest process is
killed while loading a model, try a smaller model or a more aggressively quantised one, and close
other apps. The "Default Ollama model" setting is a stored preference — the model is whatever you
name on the `ollama pull` / `ollama run` command line.

Model files live under `/root/.ollama` inside the guest and are deleted with the app.

### Node.js, git and Python 3

These are ready as soon as setup completes; they have no service to start.

```sh
node --version          # v22.11.0
npm --version
npm install -g <package>

git --version
git clone https://github.com/<owner>/<repo> ~/src/<repo>
cd ~/src/<repo> && git status

python3 --version
```

Notes:

- `git` and `python3` read and write inside the guest only (`/root`, `/usr/local`, `/tmp`). There is
  no `/sdcard` mount, so clone or download into the guest and push your work back out with `git
  push`, or read it from the Console with `cat`.
- `pip` is **not** part of the base install. Add it if you need it:
  `apt-get update && apt-get install -y python3-pip`.
- The package manager works because the installer writes `/etc/resolv.conf` and a classic
  `/etc/apt/sources.list` into the rootfs. `apt-get install -y <package>` therefore works for other
  tools too (the guest's package lists are cleaned after setup, so run `apt-get update` first).

---

## Troubleshooting

### Downloads fail or stall

- Check that you can reach GitHub, `cdimage.ubuntu.com` and `nodejs.org`; captive portals and some
  carriers block one or another.
- Retry. The installer keeps every archive it has already downloaded, so a retry resumes cheaply.
- If a download was cut off mid-file, the **partial file is kept and reused**, which then fails at
  extraction. List and delete it from the Console, then retry:

```sh
ls -lh /host-downloads
rm /host-downloads/<the-truncated-file>
```

- `HTTP 404 while fetching …` means an upstream URL changed. Please file an issue with the exact URL.
- If your network needs a proxy, the app does not support configuring one; you would need to route
  the device's traffic at the system level.

### "Cannot reach http://127.0.0.1:3080"

That is the WebView telling you nothing is listening on the port yet.

1. Go back to **Tools** and check the dsh card. If it says `installed`, tap **Start**.
2. Re-open the dashboard (**Open**), or press **Try again** on the error screen.
3. If it says `running` but the page still fails, look at the card's log output — a service can start
   and then exit immediately. Stop it and start it again.
4. Verify from the Console:

```sh
dsh --version                     # is dsh actually installed?
cat /root/.dsh/config.json        # approvalPolicy / webPort
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3080
```

`curl` is the right tool here — `netstat` and `ss` are **not** installed in this image.

5. Same procedure for OpenClaw on port `18789`.
6. Remember the Tools tab always uses the default ports; if you changed a port in Settings, start the
   service yourself from the Console with the matching flag.

### Out of storage

The installer **keeps** every archive it downloads (that is what makes retries fast), so budget for
the downloads plus the extracted copies. Check and reclaim space from the Console:

```sh
df -h /
du -sh /root/.ollama      # only if you installed Ollama
ls -lh /host-downloads
rm /host-downloads/*.tar.gz /host-downloads/*.tar.xz /host-downloads/*.zip
rm /host-downloads/*.tar.zst    # only if you are done installing Ollama — it is 1.5 GB
```

Safe to delete: the cached archives in `/host-downloads`. Do not delete `/usr/local`, `/root/.dsh`
or the runtime directory on the Android side.

### Background kills

Android reclaims background processes; the app's service processes are ordinary children of the app,
and **the app does not currently run a foreground service**, so services can be killed when the app
is backgrounded or when memory runs low.

What you can do:

1. Keep the app on screen (or at least in the recent-apps list) while a service must stay up.
2. Disable battery optimisation for **Termux All-in-One** in Android's settings — typically
   Settings → Apps → Termux All-in-One → Battery → *Unrestricted* / *Don't optimise*.
3. The *Keep services awake* switch in the Settings tab is a stored preference only; do not rely on
   it on its own.

How you notice: the Tools card flips from `running` back to `installed`, and the card's log ends with
an `-- exited with code …` line. Start the service again.

### Setup says the architecture is unsupported

`ERROR: FormatException: Unsupported CPU architecture: only arm64 and x86_64 devices are supported.`
— your device is 32-bit ARM (`armeabi-v7a`), or `uname -m` reported something else. No build exists for
it and supporting it is out of scope.

### Ollama install fails

- `apt-get install zstd` is done inside the guest as part of the Ollama install, so a broken network
  or a stale package index breaks it. Retry from the Tools tab.
- If the archive was truncated, delete it and retry:
  `rm /host-downloads/ollama-linux-arm64.tar.zst`.
- If it runs out of space mid-extraction, free space in `/host-downloads` and `/usr/local` first.

### The Console seems frozen

You probably started a foreground long-running command (`dsh web`, `ollama serve`). The Console has no
Ctrl-C and no job control, so it will look stuck until the command exits. Stop the service from the
Tools tab instead; if the shell itself is unusable, leave the Console tab and come back (the shell is
a long-lived process owned by the app), or restart the app.

### Re-running setup

**Settings → Repair / re-run installation.** It reuses cached archives, re-runs the package and npm
steps and is safe to repeat. For a completely clean environment, clear the app's data from Android's
app settings and relaunch — you will get the first-run screen again and a fresh rootfs.

---

## Uninstall

Uninstalling the app deletes **everything**: the PRoot runtime, the Ubuntu rootfs, the installed
packages, npm globals, dsh's config and any Ollama models. Nothing is written to shared storage, so
no leftovers remain on `/sdcard`.

If you need to keep something, save it *before* uninstalling — the release APK is not debuggable, so
`adb run-as` cannot reach the sandbox. Push your work to a git remote from inside the guest, or copy
it out through the Console (`cat`, base64, or `curl`/`git push`).

Reinstalling afterwards means downloading everything again, since the caches were in that sandbox.

---

## Quick command reference

Run these in the **Console** tab, inside the guest.

| Command | Purpose |
|---|---|
| `dsh --version` | Confirm dsh is installed. |
| `dsh web --port 3080 --host 127.0.0.1` | Start the dsh web UI manually (prefer the Tools tab). |
| `cat /root/.dsh/config.json` | Inspect dsh's approval policy and web port. |
| `openclaw gateway` | Start the OpenClaw gateway manually (prefer the Tools tab). |
| `ollama list` | Models you have pulled. |
| `ollama pull llama3.2:1b` | Download a small model. |
| `ollama run llama3.2:1b` | Chat with a model (needs `ollama serve` running). |
| `node --version` / `npm --version` | Confirm the Node.js toolchain. |
| `git --version` / `python3 --version` | Confirm git and Python. |
| `apt-get update && apt-get install -y <pkg>` | Add another Linux package. |
| `curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3080` | Check whether a local service is answering. |
| `df -h /` | Free space inside the guest. |
| `ls -lh /host-downloads` | Cached installer archives. |
| `ps aux` | What is running inside the guest. |

---

## Getting help

- Bugs and feature requests:
  [github.com/Allsungood/termux-dsh-allinone/issues](https://github.com/Allsungood/termux-dsh-allinone/issues)
- Architecture and internals: [ARCHITECTURE.md](ARCHITECTURE.md)
- Building from source: [BUILD.md](BUILD.md)
- Upstream projects: [dsh on npm](https://www.npmjs.com/package/@deepseek-ai/dsh) ·
  [Ollama](https://github.com/ollama/ollama) ·
  [Ubuntu base images](https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/) ·
  [PRoot build used here](https://github.com/ahmed-alnassif/proot/releases)
