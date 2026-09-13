# Termux All-in-One

**A Flutter Android app that carries its own Linux runtime.**

On first run the app downloads a static PRoot binary and an Ubuntu 24.04 root filesystem into its
own private storage, unpacks them, and installs a small toolchain inside the guest: `git`,
`python3`, `curl`, `bash`, `ripgrep`, Node.js 22 LTS, **dsh (DeepSeek Harness)**, **OpenClaw**, and
— only if you ask for it — **Ollama**.

No root. No separate Termux installation. Everything lives under one app's sandbox and is executed
through PRoot.

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Android](https://img.shields.io/badge/Android-7.0%2B%20(API%2024)-brightgreen?logo=android)
![Flutter](https://img.shields.io/badge/Flutter-stable-02569B?logo=flutter)
![Arch](https://img.shields.io/badge/Arch-arm64%20%7C%20x86--64-orange)

English | [简体中文](README.zh-CN.md)

---

## ⚠️ Verification status — read this first

**The CI pipeline builds the APKs, but the on-device runtime has not yet been verified by the
authors on a physical device.** The Dart code paths that the widget tests cover are green, and every
upstream download URL was checked for reachability before being committed, but the end-to-end flow —
first-run download, rootfs extraction, PRoot execution, `dsh web` and `openclaw gateway` coming up on
`127.0.0.1` — is **not** confirmed on real hardware.

Treat the current release as a preview and report what works and what does not in
[Issues](https://github.com/Allsungood/termux-dsh-allinone/issues).

Two more things to know up front:

- This app is **not distributable on Google Play**, because it pins `targetSdk = 28`
  ([why](#why-targetsdk-28)). It is distributed by side-loading the APK from
  [GitHub Releases](https://github.com/Allsungood/termux-dsh-allinone/releases).
- Uninstalling the app **deletes the entire environment**, including any Ollama models you
  downloaded.

---

## Requirements

| | |
|---|---|
| Android | 7.0 (API 24) or newer |
| CPU | **arm64 (aarch64)** or **x86_64** only — 32-bit ARM (`armeabi-v7a`) is not supported |
| Free storage | ~55 MB of downloads on first run, plus the unpacked rootfs and apt packages (plan for several GB); Ollama adds ~1.5 GB plus model files |
| Network | GitHub, `cdimage.ubuntu.com`, `nodejs.org`, the Ubuntu archive and the npm registry |
| Root | **not required** |

The app checks `uname -m` and refuses to continue on anything other than `aarch64`/`arm64` or
`x86_64`/`amd64` with the message *"Unsupported CPU architecture: only arm64 and x86_64 devices are
supported."*

---

## Install

1. Open [Releases](https://github.com/Allsungood/termux-dsh-allinone/releases/latest).
2. Download the APK that matches your device:
   - `termux-allinone-arm64.apk` — every normal Android phone and tablet from ~2017 onwards
   - `termux-allinone-x86_64.apk` — Android emulators, x86 Chromebooks, some tablets
3. Allow "install unknown apps" for your browser/file manager, then open the APK.
4. Launch **Termux All-in-One** and follow the first-run screen.

App identity:

| | |
|---|---|
| Application id / namespace | `com.allsungood.termux_dsh_allinone` |
| Flutter package | `termux_dsh_allinone` |
| Display name | Termux All-in-One |

---

## First run

The first screen (`SetupPage`) shows what is about to happen and a single **Install environment**
button. Pressing it downloads and installs everything while a progress bar and a live log console
show each phase:

1. Fetch and extract PRoot + loader
2. Download and extract the Ubuntu base root filesystem
3. `apt-get install git python3 curl ca-certificates xz-utils tar bash ripgrep procps`
4. Download Node.js 22.11.0 and unpack it into `/usr/local`
5. `npm install -g @deepseek-ai/dsh openclaw`, then write `/root/.dsh/config.json`
6. Verify `node` and `git`, then write a `bootstrap.complete` marker

When it finishes, **Open dashboard** takes you to the three-tab main screen. If a step fails, the
error is shown in the log and the button becomes **Retry installation**; already-downloaded archives
are reused, so a retry is cheap.

> The npm step is deliberately non-fatal: if it fails you get a warning in the log and can retry
> later from the Console with `npm install -g @deepseek-ai/dsh openclaw`.

---

## What gets downloaded

All first-run downloads are about **55 MB** in total.

| Component | Version | Files | Approx. size | Upstream |
|---|---|---|---|---|
| PRoot (static, Android) | `v26.08.25-7266fb3` | `proot-aarch64.zip` · `proot-x86_64.zip` (each contains `proot`, `loader`, `loader-m32`) | ~0.1 MB each | [ahmed-alnassif/proot releases](https://github.com/ahmed-alnassif/proot/releases) |
| Ubuntu base rootfs | `24.04.5` | `ubuntu-base-24.04.5-base-arm64.tar.gz` · `ubuntu-base-24.04.5-base-amd64.tar.gz` | 28.5 MB · 28.6 MB | [cdimage.ubuntu.com/ubuntu-base/releases/24.04/release](https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/) |
| Node.js | `22.11.0` | `node-v22.11.0-linux-arm64.tar.xz` · `node-v22.11.0-linux-x64.tar.xz` | 26.8 MB · 27.9 MB | [nodejs.org/dist/v22.11.0](https://nodejs.org/dist/v22.11.0/) |
| dsh + OpenClaw | latest on npm at install time | — | (npm) | `npm install -g @deepseek-ai/dsh openclaw` |
| **Ollama (optional, user-triggered)** | `v0.34.0` | `ollama-linux-arm64.tar.zst` · `ollama-linux-amd64.tar.zst` | **~1.5 GB** | [ollama/ollama releases](https://github.com/ollama/ollama/releases) |

Everything is fetched over HTTPS from the addresses above and unpacked into
`/data/data/com.allsungood.termux_dsh_allinone/files/runtime/`.

In the guest, the base packages are `git`, `python3`, `curl`, `ca-certificates`, `xz-utils`, `tar`,
`bash`, `ripgrep` and `procps`; Node.js 22 LTS is extracted into `/usr/local`, and `dsh` and
`openclaw` are installed globally with npm.

**Why Ubuntu and not Alpine?** dsh's native modules ship **glibc** prebuilds. A musl distribution
such as Alpine would not load them, so the runtime uses Ubuntu 24.04 (glibc) as the guest.

---

## The three tabs

| Tab | What it does |
|---|---|
| **Tools** | Dashboard grid with one card per tool (`dsh`, OpenClaw, Ollama, Node.js, Git, Python 3). Each card shows `running` / `installed` / `not installed` / `missing`, and offers **Start**, **Stop** and **Open** where they apply. Ollama has an **Install** button because it is optional. Pull down to re-probe. A summary card reports "N of 6 tools ready inside the app sandbox". |
| **Console** | An on-screen shell inside the guest, with a row of quick-command chips (`dsh --version`, `dsh web --port 3080`, `openclaw gateway`, `ollama list`, `node --version`, `python3 --version`). It is a **piped shell, not a PTY** — see [limitations](#limitations). |
| **Settings** | dsh web UI port, OpenClaw gateway port, Ollama port, default Ollama model, a keep-awake switch, and **Repair / re-run installation**. |

Long-running services (`dsh web`, `openclaw gateway`, `ollama serve`) are started from the **Tools**
tab, which runs them as background guest processes and keeps their output. **Open** loads the local
dashboard in an in-app WebView (`http://127.0.0.1:3080` for dsh, `http://127.0.0.1:18789` for
OpenClaw) with a reload button and an "open in browser" button.

---

## Why targetSdk 28

Android 10 (API 29) introduced a **W^X restriction**: an app whose `targetSdk` is 29 or higher may no
longer `execve` a file that it wrote into its own data directory.

This app's entire purpose is executing PRoot plus a Linux root filesystem that it unpacked itself, so
that restriction would break it completely. The build therefore pins:

- `minSdk = 24`
- `targetSdk = 28`

Termux pins a low `targetSdk` for exactly the same reason. The consequence is that the app cannot be
published on Google Play, so releases are side-loaded APKs from GitHub Releases.

---

## Repository layout

```
termux-dsh-allinone/
├── .github/
│   ├── scripts/patch_android.py   # patches the generated Android project (minSdk/targetSdk/label/permissions)
│   └── workflows/build.yml        # the only workflow: scaffolds, patches, tests, builds 2 APKs, releases on v* tags
├── docs/
│   ├── ARCHITECTURE.md            # PRoot exec model, data flow, why glibc, why targetSdk 28, security posture
│   ├── USER_GUIDE.md              # install, first run, tabs, per-tool usage, troubleshooting
│   └── BUILD.md                   # local build, CI patching, adding tools, version pins, release checklist
├── flutter_app/
│   ├── lib/core/runtime.dart      # PRoot/rootfs paths, downloader, RuntimeSources version pins, first-run installer
│   ├── lib/models/                # EnvironmentConfig (settings), ToolStatus (dashboard catalogue)
│   ├── lib/pages/                 # SetupPage, HomePage, TaskPage, WebDashboardPage
│   ├── lib/services/              # EnvironmentService (probe/start/stop), TerminalService (console shell)
│   ├── lib/views/                 # DashboardView, ConsoleView, SettingsView
│   ├── lib/widgets/               # ToolCard, StatusCard
│   ├── test/widget_test.dart      # widget/unit tests
│   └── pubspec.yaml
├── LICENSE
├── README.md
└── README.zh-CN.md
```

There is deliberately **no committed `android/` directory**: CI runs `flutter create` to scaffold one
that matches the installed Flutter version, then patches it. See [docs/BUILD.md](docs/BUILD.md).

Flutter dependencies: `shared_preferences`, `path_provider`, `webview_flutter`, `url_launcher`,
`archive`.

---

## Limitations

Please read these before you install. They are design constraints, not temporary bugs.

- **The runtime has not been verified on a physical device.** CI builds the APK; nobody has yet
  proven the full first-run flow end to end on real hardware.
- **The Console is a piped shell, not a PTY.** Ordinary commands work. Full-screen curses programs
  (`vi`, `nano`, `htop`, `top`) do not. `dsh web` and `openclaw gateway` are started as background
  services from the **Tools** tab, not by typing them at the console prompt.
- **No Google Play distribution.** `targetSdk = 28` is mandatory for this design, so releases are
  side-loaded from GitHub Releases.
- **Ollama is a ~1.5 GB download**, it is extracted with `tar --zstd` *inside* the guest (Android's
  bundled `tar` has no zstd support), and a model may simply not fit in your device's RAM.
- **Everything runs inside one app's private storage.** Uninstalling the app deletes the whole
  environment — rootfs, toolchain, npm globals, and any downloaded models. There is no shared-storage
  bind, so the guest cannot browse `/sdcard`.
- **32-bit ARM is not supported.** arm64 or x86_64 only.
- **The guest is `root` only in the PRoot sense.** `-0` makes the guest see uid 0; it grants nothing
  beyond the app's own Android sandbox.

More detail, including the security posture, is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Documentation

- [docs/USER_GUIDE.md](docs/USER_GUIDE.md) — install, first run, every tab, per-tool usage, troubleshooting
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — component diagram, first-run data flow, the PRoot exec model
- [docs/BUILD.md](docs/BUILD.md) — building locally, how CI scaffolds and patches, adding tools, release checklist
- [README.zh-CN.md](README.zh-CN.md) — 简体中文说明

---

## License

MIT — see [LICENSE](LICENSE).
