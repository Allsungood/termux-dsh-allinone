# Architecture

Termux All-in-One is a Flutter Android application that carries its **own** Linux runtime. It does
not use Termux, it does not need root, and it does not touch anything outside its own app sandbox.

> **Verification status.** The CI pipeline builds both APKs and the Dart code is covered by widget
> tests, but the runtime described here — first-run download, rootfs extraction, PRoot execution,
> the `dsh web` and `openclaw gateway` services — **has not been verified on a physical device**.
> This document describes what the code does; it is not a report of a successful device test.

---

## 1. Component diagram

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ Android device — NO root, no system modification                                     │
│                                                                                      │
│  ┌────────────────────────────────────────────────────────────────────────────────┐  │
│  │ App sandbox: com.allsungood.termux_dsh_allinone                                │  │
│  │                                                                                │  │
│  │  Flutter / Dart                                                                │  │
│  │  ┌──────────────────────────────────────────────────────────────────────────┐  │  │
│  │  │ main.dart                                                                │  │  │
│  │  │   isBootstrapped() ? HomePage : SetupPage                                │  │  │
│  │  │                                                                          │  │  │
│  │  │   SetupPage            HomePage (IndexedStack + NavigationBar)           │  │  │
│  │  │   └ RuntimeBootstrap   ├── Tools    → DashboardView  (ToolCard grid)     │  │  │
│  │  │                        ├── Console  → ConsoleView    (piped shell)       │  │  │
│  │  │                        └── Settings → SettingsView   (ports, repair)     │  │  │
│  │  │                                                                          │  │  │
│  │  │   TaskPage  ── reusable "run this job and show the log" screen           │  │  │
│  │  │               (Ollama install, repair / re-run installation)             │  │  │
│  │  │   WebDashboardPage ── in-app WebView for the loopback dashboards         │  │  │
│  │  ├──────────────────────────────────────────────────────────────────────────┤  │  │
│  │  │ EnvironmentService      TerminalService      EnvironmentConfig           │  │  │
│  │  │  probe() / startTool()   long-lived shell     SharedPreferences JSON     │  │  │
│  │  │  stopTool() / runSetup() (stdin pipe)                                    │  │  │
│  │  │ RuntimeSources          RuntimePaths          Downloader                 │  │  │
│  │  │  version pins            files/runtime/...     HttpClient + progress     │  │  │
│  │  └───────────────────────────────────┬──────────────────────────────────────┘  │  │
│  │                                      │ dart:io Process (no native bridge)      │  │
│  │                                      ▼                                         │  │
│  │  /data/data/com.allsungood.termux_dsh_allinone/files/runtime/                  │  │
│  │  ├── proot              static PRoot binary (mode 700)                         │  │
│  │  ├── loader             PRoot loader (mode 700)                                │  │
│  │  ├── rootfs/            Ubuntu 24.04.5 userland                                │  │
│  │  ├── downloads/         cached archives (also bound as /host-downloads)        │  │
│  │  ├── tmp/               PROOT_TMP_DIR                                          │  │
│  │  └── bootstrap.complete written at the end of a successful setup               │  │
│  │                                      │                                         │  │
│  │                                      ▼                                         │  │
│  │  Guest (PRoot, uid 0 *inside the guest only*)                                  │  │
│  │  ┌──────────────────────────────────────────────────────────────────────────┐  │  │
│  │  │ /usr/bin  git · python3 · curl · bash · ripgrep · tar · xz · procps      │  │  │
│  │  │ /usr/local/bin  node · npm · dsh · openclaw · (ollama, optional)         │  │  │
│  │  │ /root/.dsh/config.json  {"approvalPolicy":"never","webPort":3080}        │  │  │
│  │  │ host binds: /dev · /proc · /sys · downloads → /host-downloads            │  │  │
│  │  └──────────────────────────────────────────────────────────────────────────┘  │  │
│  │                                      │                                         │  │
│  │                                      ▼                                         │  │
│  │  Loopback services   dsh web :3080   openclaw gateway :18789   ollama :11434   │  │
│  │                                      │                                         │  │
│  │                     WebView ◄────────┘  http://127.0.0.1:<port>                │  │
│  └────────────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

There is **no Kotlin/native bridge**. Every interaction with the runtime is a plain `dart:io`
`Process` spawn of the PRoot binary inside the app's own data directory. The only Android-native code
that exists is whatever `flutter create` generates, plus the manifest/Gradle patches applied by
[`.github/scripts/patch_android.py`](../.github/scripts/patch_android.py).

---

## 2. On-disk layout

`RuntimePaths.resolve()` calls `getApplicationSupportDirectory()` and appends `runtime`, which on
Android is:

```
/data/data/com.allsungood.termux_dsh_allinone/files/runtime/
```

| Path | Purpose |
|---|---|
| `proot` | The static PRoot binary, `chmod 700` after extraction |
| `loader` | PRoot's loader, `chmod 700`; exported to the guest as `PROOT_LOADER` |
| `rootfs/` | The Ubuntu 24.04.5 userland (`--rootfs` target) |
| `downloads/` | Cached upstream archives; bind-mounted into the guest as `/host-downloads` |
| `tmp/` | `PROOT_TMP_DIR` |
| `bootstrap.complete` | Written by the last phase of setup; `isBootstrapped()` is just `marker.exists()` |

Two finer-grained idempotency checks exist inside setup: `rootfs/etc/os-release` decides whether the
Ubuntu tarball must be extracted, and each archive in `downloads/` is only re-fetched when the file is
missing. Downloads are **not** deleted after extraction, which makes retries and repairs fast at the
cost of disk space.

---

## 3. First-run data flow

`RuntimeBootstrap.run()` executes six phases. Each phase reports into a single progress bar through a
weight table — `[0.05, 0.15, 0.30, 0.20, 0.20, 0.10]` — and every user-visible line goes to the log
console on `SetupPage`.

| # | Weight | What happens |
|---|---|---|
| 0 | 5% | `DeviceArch.detect()` runs `uname -m`; anything other than aarch64/arm64 or x86_64/amd64 throws `FormatException`. Then download `proot-<arch>.zip` (if absent), extract it with the pure-Dart `ZipDecoder`, and `chmod 700` both `proot` and `loader`. |
| 1 | 15% | If `rootfs/etc/os-release` is absent: download `ubuntu-base-24.04.5-base-<arch>.tar.gz` (if absent) and extract it with the **host** `tar -xzf`. |
| 2 | 30% | Write `/etc/resolv.conf` (`1.1.1.1`, `8.8.8.8`) and a classic `/etc/apt/sources.list` for `noble`, then run `apt-get update && apt-get install -y --no-install-recommends git python3 curl ca-certificates xz-utils tar bash ripgrep procps` inside the guest and drop `/var/lib/apt/lists/*`. A non-zero exit aborts setup. |
| 3 | 20% | Download `node-v22.11.0-linux-<arch>.tar.xz` (if absent) and unpack it **inside the guest** with `tar -xJf /host-downloads/... -C /usr/local --strip-components=1`; then run `/usr/local/bin/node --version` to prove it works. |
| 4 | 20% | `/usr/local/bin/npm install -g --no-fund --no-audit @deepseek-ai/dsh openclaw`, then write `/root/.dsh/config.json`. **A non-zero exit is only a warning** — the toolchain is still usable and the user can retry from the Console. |
| 5 | 10% | Run `node --version; git --version` in the guest and write the `bootstrap.complete` marker (arch + Node version + timestamp). |

`installOllama()` is a *separate*, user-triggered path (Tools tab → Ollama → **Install**): download
the ~1.5 GB `ollama-linux-<arch>.tar.zst`, then — inside the guest — `apt-get install zstd`,
`tar --zstd -xf /host-downloads/... -C /usr/local`, `chmod 755 /usr/local/bin/ollama`, and
`ollama --version`. It runs with a 60-minute timeout instead of the default 20.

### Why extraction happens in two different places

| Archive | Extracted by | Why |
|---|---|---|
| `proot-*.zip` | Pure Dart (`ZipDecoder`) | Contains three regular files and no symlinks, so no host tool is needed. |
| `ubuntu-base-*.tar.gz` | Host `tar` (`tar -xzf`) | An Ubuntu rootfs is full of symlinks (`/bin -> usr/bin`); the host `tar` preserves them. |
| `node-*.tar.xz` | Guest `tar -xJf` | Runs after the rootfs exists, so it can write straight into the guest `/usr/local`. |
| `ollama-*.tar.zst` | Guest `tar --zstd` | **Android's bundled `tar` has no zstd support**, so `zstd` is installed from the Ubuntu archive and the extraction is done inside the guest. |

---

## 4. The PRoot exec model

Everything the guest runs goes through one argv template (`ProotRuntime.guestArgs`):

```
proot --link2symlink -0 -r <runtime>/rootfs \
      -b /dev -b /proc -b /sys \
      -b <runtime>/downloads:/host-downloads \
      -w /root \
      <command...>
```

| Flag | Reason |
|---|---|
| `--link2symlink` | Android filesystems refuse hard links across some boundaries; PRoot emulates them with symlinks. |
| `-0` | The guest sees uid 0. This is PRoot's fake-root, **not** a privilege escalation. |
| `-r <rootfs>` | The Ubuntu userland becomes `/`. |
| `-b /dev -b /proc -b /sys` | The guest gets the device, process and sysfs views it needs. |
| `-b downloads:/host-downloads` | Files downloaded on the Android side are handed to the guest without copying them into the rootfs. |
| `-w /root` | Working directory. |

The child environment is built **from scratch** — `includeParentEnvironment: false` — so nothing from
the Android side leaks in:

```json
{
  "PROOT_LOADER":  "<runtime>/loader",
  "PROOT_TMP_DIR": "<runtime>/tmp",
  "HOME":          "/root",
  "PATH":          "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
  "TERM":          "xterm-256color",
  "LANG":          "C.UTF-8",
  "DEBIAN_FRONTEND": "noninteractive"
}
```

Three call styles sit on top of that template:

1. **`ProotRuntime.run()`** — `Process.run`, captures stdout/stderr, default timeout 20 minutes.
   Used for the architecture probe, `node --version`, and writing the dsh config.
2. **`ProotRuntime.stream()`** — `Process.start` + `/bin/sh -c "<command>"`, forwarding stdout and
   stderr line by line into the log callback, returning the exit code. Used for `apt-get`, `tar`,
   `npm` and the Ollama install.
3. **Long-lived services** — `EnvironmentService.startTool()` spawns
   `proot ... /bin/sh -c "<tool.startCommand>"`, keeps the `Process` in a map keyed by tool id, and
   buffers up to 400 log lines per tool. `stopTool()` sends `SIGTERM`. Services are therefore
   **background guest processes owned by the app**, not children of the Console shell.

### Services and the Console

| | Tools tab (`EnvironmentService`) | Console tab (`TerminalService`) |
|---|---|---|
| Process | one PRoot process per started tool | one long-lived `proot ... /bin/sh` |
| Input | none | `process.stdin.writeln(command)` |
| Output | per-tool ring buffer (400 lines) | broadcast stream, UI keeps 2000 lines |
| Stop | **Stop** button → `SIGTERM` | stops when the shell exits; there is no in-app kill button |

The Console is a **piped shell, not a PTY**. There is no `termios`, no window size, no job control
and no way to send `Ctrl-C` from the UI. Ordinary line-oriented commands work; full-screen curses
programs (`vi`, `nano`, `htop`, `top`) do not, and a long-running foreground command will simply look
like a hung console. That is exactly why `dsh web`, `openclaw gateway` and `ollama serve` are started
from the Tools tab instead.

### Service endpoints

| Service | Start command | Dashboard |
|---|---|---|
| dsh | `dsh web --port 3080 --host 127.0.0.1` | `http://127.0.0.1:3080` |
| OpenClaw | `openclaw gateway` | `http://127.0.0.1:18789` |
| Ollama | `ollama serve` | none (no WebView page; port 11434) |

`ToolStatus.catalog()` holds these strings as constants, which means the port fields in the Settings
tab are **stored preferences today, not inputs to the launch commands**: the Tools tab always starts
the built-in defaults. If you change a port in Settings, start the service from the Console with a
matching flag instead.

The dsh config is pre-seeded with `{"approvalPolicy":"never","webPort":3080}` because the product
requirement is a launcher that never stalls on an approval prompt — see the security notes below for
what that costs.

---

## 5. Why Ubuntu (glibc) and not Alpine (musl)

dsh's native modules are published as **glibc** prebuilds. A musl distribution would fail to load
them, so the guest is an Ubuntu 24.04.5 base rootfs and Node.js comes from the official linux
tarball rather than a distribution package. The cost is size: the Ubuntu base tarball is ~28.5 MB
versus a few MB for a minimal musl rootfs.

---

## 6. Why minSdk 24 and targetSdk 28

Android 10 (API 29) introduced a **W^X restriction**: an app with `targetSdk >= 29` may not `execve` a
file it wrote into its own data directory. This app's entire purpose is executing PRoot and a Linux
root filesystem it unpacked itself, so pinning below 29 is not a preference — it is the only way the
design works. Termux pins a low `targetSdk` for the same reason.

Consequences:

- **Not distributable on Google Play.** Play requires a recent `targetSdk`; this build is
  side-loaded from GitHub Releases.
- `minSdk = 24` (Android 7.0) keeps the addressable device range wide; nothing in the runtime needs
  newer APIs.

The patch script asserts that exactly one `minSdk` and one `targetSdk` reference exist in the
generated Gradle file, so a change in Flutter's template fails the build loudly instead of silently
producing a broken APK.

---

## 7. Security posture

### What the design gives you

| Property | How |
|---|---|
| No root, no system modification | Everything lives in one app sandbox; no `su`, no setuid helper, no shared-storage install. |
| No separate terminal app to trust | There is no Termux dependency and no bootstrap zip imported from elsewhere at runtime. |
| Installer downloads use HTTPS | Every URL in `RuntimeSources` is HTTPS. Note that `apt-get` talks to `http://archive.ubuntu.com` over plain HTTP — standard Ubuntu apt behaviour, with package authenticity coming from APT's signatures rather than TLS. |
| Small attack surface in the app itself | No custom native code, only generated-and-patched Android project files. |
| Clean removal | Uninstalling the app removes the sandbox, and with it the whole environment. |

### What you should be aware of

| Risk | Reality |
|---|---|
| **`approvalPolicy: "never"`** | dsh is pre-configured never to ask before acting. That is deliberate — the launcher must not stall on a prompt — but it means dsh will not request confirmation for the commands it decides to run. Change `/root/.dsh/config.json` from the Console if you want a different policy. |
| **Guest "root" is fake** | `-0` makes the guest *see* uid 0. It grants no capability the app does not already have; the process is still the app's own Linux uid under Android's sandbox. |
| **Host `/dev`, `/proc`, `/sys` are bound in** | Guest code can observe host devices and processes to the extent the app's uid allows. This is required for a usable Linux userland, but it is a real boundary crossing. |
| **Cleartext HTTP is enabled app-wide** | The manifest sets `android:usesCleartextTraffic="true"` so the WebView can load `http://127.0.0.1:<port>`. The flag is not limited to loopback, and the WebView runs with JavaScript unrestricted and no URL allowlist. Only navigate to the local dashboards you started yourself. |
| **`/sdcard` is not mounted** | The guest cannot read your shared storage, which limits accidental data exposure — but it also means there is no in-app file import/export path. |
| **No artifact verification beyond HTTPS** | The app does not check checksums or signatures of the upstream archives; it trusts the four HTTPS sources. Verify the pinned versions yourself if that matters to you. |
| **Any code run inside the guest is the app's code** | Once installed, arbitrary binaries in the rootfs run with the app's identity. |
| **Not on Google Play** | No store review, no Play Protect attestation path; you are installing a sideloaded APK. |

The app declares these permissions (added by the patch script): `INTERNET`, `ACCESS_NETWORK_STATE`,
`WAKE_LOCK`, `FOREGROUND_SERVICE`, `POST_NOTIFICATIONS`, `READ_EXTERNAL_STORAGE`,
`WRITE_EXTERNAL_STORAGE`.

Note that `FOREGROUND_SERVICE` and `WAKE_LOCK` are declared and the Settings tab stores a
`keepAwake` preference, but the repository contains **no foreground-service or wake-lock
implementation** — no native service code is committed. Services therefore live as ordinary child
processes of the app and are subject to Android's background limits. See
[USER_GUIDE.md](USER_GUIDE.md#background-kills) for the practical consequences.

---

## 8. Configuration and persistence

The Settings tab writes a single JSON blob into `SharedPreferences` under the key
`environment_config`:

```json
{
  "dshPort": 3080,
  "openclawPort": 18789,
  "ollamaPort": 11434,
  "ollamaModel": "llama3.2:1b",
  "keepAwake": true
}
```

Ports are validated to be integers in `1..65535` and the model name to be non-empty before saving.
Everything the runtime needs beyond this lives inside the guest (`/root/.dsh/config.json`,
`/root/.ollama/`, and so on) and is therefore deleted with the app.

---

## 9. Build architecture

```
GitHub Actions  (.github/workflows/build.yml — the only workflow)
  │
  ├─ actions/checkout@v4 · setup-java 17 · subosito/flutter-action@v2 (stable)
  │
  ├─ flutter create --platforms=android --org com.allsungood \
  │     --project-name termux_dsh_allinone "$RUNNER_TEMP/scaffold"
  │     → rm -rf flutter_app/android; cp -r scaffold/android flutter_app/android
  │
  ├─ python3 .github/scripts/patch_android.py
  │     → minSdk 24, targetSdk 28, app label, usesCleartextTraffic, 7 permissions
  │     → every substitution is asserted
  │
  ├─ flutter pub get · flutter analyze --no-fatal-infos --no-fatal-warnings · flutter test
  │
  ├─ flutter build apk --release --target-platform android-arm64
  │     → termux-allinone-arm64.apk
  ├─ flutter build apk --release --target-platform android-x64
  │     → termux-allinone-x86_64.apk
  │
  ├─ actions/upload-artifact@v4 (artifact name: termux-allinone-apks)
  └─ softprops/action-gh-release@v2 — only when the ref is a v* tag
        → attaches termux-allinone-arm64.apk and termux-allinone-x86_64.apk
```

The Android project is generated rather than committed so that it always matches the installed
Flutter version — including the binary Gradle wrapper, which cannot be authored by hand in a text
diff. [BUILD.md](BUILD.md) covers the same steps for a local build.

---

## 10. What is *not* verified

To be explicit about the boundary of what has been checked:

- Every upstream URL in `RuntimeSources` was confirmed reachable before being committed, and the
  download/extract/probe code paths are exercised by review and static analysis.
- `flutter analyze` and `flutter test` run in CI; the tests cover `ToolCard`, `StatusCard` and the
  tool catalogue — they never touch PRoot or a real guest.
- **Nothing beyond that.** No physical-device run of the first-run flow, of `dsh web`, of
  `openclaw gateway`, or of Ollama has been performed by the authors.
