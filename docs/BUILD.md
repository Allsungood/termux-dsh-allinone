# Build Guide

How to build Termux All-in-One locally, how CI scaffolds and patches the Android project, how to add
a dependency or a whole new tool, how to move the pinned runtime versions, and what to check before a
release.

- [Prerequisites](#prerequisites)
- [Build locally](#build-locally)
- [Why the Android project is generated, not committed](#why-the-android-project-is-generated-not-committed)
- [What patch_android.py does](#what-patch_androidpy-does)
- [The CI workflow](#the-ci-workflow)
- [Pinned runtime versions](#pinned-runtime-versions)
- [Adding a Flutter dependency](#adding-a-flutter-dependency)
- [Adding a new tool](#adding-a-new-tool)
- [Signing](#signing)
- [Release checklist](#release-checklist)
- [Build troubleshooting](#build-troubleshooting)

> **Note.** This document describes the build. It does **not** claim the resulting APK has been
> verified on a device — it has not. Verify on hardware before you announce a release.

---

## Prerequisites

| Component | Version | Why |
|---|---|---|
| Flutter SDK | stable channel | CI uses `subosito/flutter-action@v2` with `channel: stable` and `cache: true`. |
| Dart SDK | `>=3.5.0 <4.0.0` | Constraint in `flutter_app/pubspec.yaml`. |
| JDK | 17 | CI sets `JAVA_VERSION: '17'` (Temurin). |
| Android SDK | whatever your Flutter version wants | Run `flutter doctor` and accept the licences. There is no committed Android project, so `compileSdk` follows your Flutter version. |
| Python 3 | any 3.x | `patch_android.py` is stdlib-only (`pathlib`, `re`, `sys`). |
| git | any | To clone the repository. |

No Linux, no `proot`, no `apk`, no QEMU and no cross-compilation are needed: **the Linux runtime is
downloaded on the device at first run, not built here.** The APK contains only Dart code.

```bash
git clone https://github.com/Allsungood/termux-dsh-allinone.git
cd termux-dsh-allinone
```

---

## Build locally

### 1. Scaffold the Android platform (exactly as CI does)

The repository has no `android/` directory, so there is nothing to build until you generate one.
Generate it in a temp directory and copy only the `android` folder in — that keeps `--org` and
`--project-name` correct instead of letting `flutter create` infer them from the folder name:

```bash
cd flutter_app

flutter create \
  --platforms=android \
  --org com.allsungood \
  --project-name termux_dsh_allinone \
  "$TMPDIR/scaffold"

rm -rf android
cp -r "$TMPDIR/scaffold/android" android
```

On Windows PowerShell:

```powershell
cd flutter_app
flutter create --platforms=android --org com.allsungood `
  --project-name termux_dsh_allinone "$env:TEMP\scaffold"
Remove-Item -Recurse -Force android -ErrorAction SilentlyContinue
Copy-Item -Recurse "$env:TEMP\scaffold\android" android
```

This yields `applicationId` and `namespace` `com.allsungood.termux_dsh_allinone`. It also produces the
binary Gradle wrapper, which is why it cannot be replaced by a hand-written file.

### 2. Patch it

```bash
python3 .github/scripts/patch_android.py
```

(On Windows: `python .github\scripts\patch_android.py`, run from the repository root.)

### 3. Resolve, check, test, build

```bash
cd flutter_app
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release --target-platform android-arm64
```

Output: `flutter_app/build/app/outputs/flutter-apk/app-release.apk`.

For a 64-bit x86 device or emulator, repeat with `--target-platform android-x64`.

### 4. Install it on a device

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Or copy the APK to the device and tap it. First launch goes straight to the setup screen because the
`bootstrap.complete` marker does not exist yet.

---

## Why the Android project is generated, not committed

Every CI run regenerates `flutter_app/android` from scratch:

```
flutter create --platforms=android --org com.allsungood \
  --project-name termux_dsh_allinone "$RUNNER_TEMP/scaffold"
rm -rf android && cp -r "$RUNNER_TEMP/scaffold/android" android
```

Reasons:

- The generated project always matches the installed Flutter version — Gradle plugin versions,
  `compileSdk`, and the **binary Gradle wrapper JAR**, which cannot be reviewed as a text diff.
- There is no drift to maintain: nothing in the app needs custom Kotlin, custom resources or an
  `AndroidManifest` of its own beyond two pins and a handful of flags.
- The only Android-specific requirements are therefore expressed as a **diff applied to the
  generated output**, in `.github/scripts/patch_android.py`, which is reviewable in one screen.

The trade-off: you cannot hand-edit `flutter_app/android` and expect it to survive. Any Gradle or
manifest change belongs in `patch_android.py`.

---

## What `patch_android.py` does

It resolves the repository root as `parents[2]` of the script file and edits
`flutter_app/android`, failing the build (with a `::error::` annotation and exit code 1) if any
assumption does not hold.

### 1. `app/build.gradle.kts` or `app/build.gradle`

| Substitution | Value |
|---|---|
| `flutter.minSdkVersion` | `24` |
| `flutter.targetSdkVersion` | `28` |

Both regexes must match **exactly once**, otherwise the script fails. That is intentional: if
Flutter's template changes shape, you want a loud failure, not a silently mis-pinned APK.

**Why these pins exist.** Android 10 (API 29) introduced a W^X restriction: an app with
`targetSdk >= 29` may not `execve` a file it wrote into its own data directory. This app's whole
purpose is executing PRoot and a Linux root filesystem that it unpacked into its own data directory,
so `targetSdk` must stay below 29. Termux pins a low `targetSdk` for the same reason. The consequence
is that the app is **not distributable on Google Play**; releases are side-loaded. See
[ARCHITECTURE.md](ARCHITECTURE.md#6-why-minsdk-24-and-targetsdk-28).

### 2. `app/src/main/AndroidManifest.xml`

| Change | Value |
|---|---|
| `android:label` | `Termux All-in-One` |
| `android:usesCleartextTraffic` | `true` — added if absent, before `<application>` |
| Permissions | Any of the seven below that are missing are inserted before `<application>` |

```text
android.permission.INTERNET
android.permission.ACCESS_NETWORK_STATE
android.permission.WAKE_LOCK
android.permission.FOREGROUND_SERVICE
android.permission.POST_NOTIFICATIONS
android.permission.READ_EXTERNAL_STORAGE
android.permission.WRITE_EXTERNAL_STORAGE
```

Cleartext HTTP is required because the dashboards are served on `http://127.0.0.1:<port>`, and
Android 9+ blocks cleartext by default. Note that the flag is app-wide, not loopback-only — see the
security notes in [ARCHITECTURE.md](ARCHITECTURE.md#7-security-posture).

If the script reports `was not modified`, the generated project already had every change (unlikely)
or a regex silently matched nothing — read the failure message, it names the file.

---

## The CI workflow

There is exactly **one** workflow: `.github/workflows/build.yml` (there is no separate test
workflow; checks run inside it).

| Trigger | Effect |
|---|---|
| `push` to `master` / `main` | Build both APKs, upload them as artifacts. No release. |
| `push` of a `v*` tag | Same, plus attaching both APKs to a GitHub Release. |
| `pull_request` targeting `master` / `main` | Same as a branch push. |
| `workflow_dispatch` | Manual run. |

Single job `build-apk` on `ubuntu-latest`, `timeout-minutes: 45`, `permissions: contents: write`.

Steps, in order:

1. `actions/checkout@v4`
2. `actions/setup-java@v4` — Temurin, Java 17
3. `subosito/flutter-action@v2` — stable channel, cached
4. **Scaffold the Android platform** (`flutter create` into `$RUNNER_TEMP/scaffold`, copy `android`)
5. **Patch the Android project** (`python3 .github/scripts/patch_android.py`)
6. `flutter pub get`
7. `flutter analyze --no-fatal-infos --no-fatal-warnings`
8. `flutter test`
9. `flutter build apk --release --target-platform android-arm64` → staged as `termux-allinone-arm64.apk`
10. `flutter build apk --release --target-platform android-x64` → staged as `termux-allinone-x86_64.apk`
11. `actions/upload-artifact@v4` — artifact name `termux-allinone-apks`, `if-no-files-found: error`
12. `softprops/action-gh-release@v2` — only when `github.ref` starts with `refs/tags/v`;
    `generate_release_notes: true`, `fail_on_unmatched_files: true`

Release asset names are exactly:

```
termux-allinone-arm64.apk
termux-allinone-x86_64.apk
```

Keep those names stable — the READMEs and the user guide tell people to download them by name.

To emulate CI locally, run steps 4–10 by hand as shown in [Build locally](#build-locally).

---

## Pinned runtime versions

**All upstream versions live in one place: `RuntimeSources` in
[`flutter_app/lib/core/runtime.dart`](../flutter_app/lib/core/runtime.dart)**, together with the
per-architecture asset names in the `DeviceArch` enum in the same file.

| Constant / getter | Current value | Drives |
|---|---|---|
| `RuntimeSources.prootVersion` | `v26.08.25-7266fb3` | `prootBase` → `https://github.com/ahmed-alnassif/proot/releases/download/<version>/` |
| `DeviceArch.prootAsset` | `proot-aarch64.zip` / `proot-x86_64.zip` | The PRoot download and the extracted `proot` + `loader` |
| `RuntimeSources.ubuntuBase` | `https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release` | Rootfs download base |
| `DeviceArch.ubuntuAsset` | `ubuntu-base-24.04.5-base-arm64.tar.gz` / `…-amd64.tar.gz` | Rootfs download, extraction, and the `rootfs.source` identity marker |
| `RuntimeSources.nodeVersion` | `22.11.0` | `nodeBase` → `https://nodejs.org/dist/v<version>/`, the tarball name, the setup log and the `bootstrap.complete` marker |
| `DeviceArch.nodeDir` | `node-v22.11.0-linux-arm64` / `…-x64` | Node tarball name and the in-guest `tar -xJf` |
| `RuntimeSources.ollamaVersion` | `v0.34.0` | `ollamaUrl` → `https://github.com/ollama/ollama/releases/download/<version>/` |
| `DeviceArch.ollamaAsset` | `ollama-linux-arm64.tar.zst` / `ollama-linux-amd64.tar.zst` | Optional Ollama download and in-guest `tar --zstd` |

Also derived from the code rather than from a constant: `DeviceArch.detect()` parses `uname -m` and
accepts only `aarch64`/`arm64` and `x86_64`/`amd64`; the apt package list is a literal string in
phase 2 of `RuntimeBootstrap.run()`; and the npm packages are `@deepseek-ai/dsh openclaw`.

### How to change a pinned version

1. Edit the constant(s) **and** every place the version string is duplicated — for Ubuntu that means
   `ubuntuBase` (URL) *and* `DeviceArch.ubuntuAsset` (filename); for Node it means `nodeVersion` and
   `DeviceArch.nodeDir`; PRoot and Ollama take their version from `prootVersion` / `ollamaVersion`
   and the cache name is stamped automatically by `cachedProot()` / `cachedOllama()`.
2. Confirm the asset actually exists with the new name (the downloader throws
   `HTTP <code> while fetching <url>` on anything that is not 200).
3. Update the download table in [README.md](../README.md) and
   [README.zh-CN.md](../README.zh-CN.md) with the new version, file names and sizes.
4. Re-run `flutter analyze`, `flutter test` and a local build.

### Cached-archive gotchas (read before you ship a bump)

The installer only downloads when the destination file is **absent**, and it never deletes the
archives afterwards. Each artifact is cached under a name that embeds its pinned version, so a
version bump is a cache miss and therefore does reach an existing install:

| Bumped | Cached as | Reaches an existing install? |
|---|---|---|
| `nodeVersion` | `node-v<version>-linux-<arch>.tar.xz` | Yes — new filename → re-download, and Node is re-extracted on every setup run. |
| `DeviceArch.ubuntuAsset` | `ubuntu-base-<version>-base-<arch>.tar.gz` | Yes — the new tarball is downloaded **and** unpacked, because the identity in `rootfs.source` no longer matches. |
| `prootVersion` | `<prootVersion>-proot-<arch>.zip` (via `cachedProot()`) | Yes — the version is part of the local filename, so the stale zip is not reused. |
| `ollamaVersion` | `<ollamaVersion>-ollama-linux-<arch>.tar.zst` (via `cachedOllama()`) | Yes — same reason. |

`cachedProot()` / `cachedOllama()` exist precisely because upstream names those two archives
*without* a version; caching them under the upstream name would silently keep the old binary.

Old archives are never pruned, so `downloads/` grows by roughly the size of each superseded
release and the ~1.5 GB Ollama tarball stays behind after installation. Clearing the app's data is
what actually reclaims the space.

---

## Adding a Flutter dependency

```bash
cd flutter_app
flutter pub add <package>
```

Commit the updated `pubspec.yaml` and `pubspec.lock`. CI runs `flutter pub get` on the committed
pubspec, so nothing else is required — no Android-side change, because the Android project is
regenerated on every build.

Current dependencies: `shared_preferences`, `path_provider`, `webview_flutter`, `url_launcher`,
`archive` (plus `cupertino_icons` and the dev dependencies `flutter_test`, `flutter_lints`).

Lint configuration lives in `flutter_app/analysis_options.yaml` (`package:flutter_lints/flutter.yaml`
plus `prefer_const_constructors`, `prefer_const_literals_to_create_immutables`, `avoid_print: false`).

---

## Adding a new tool

There is no bootstrap recipe and no package list file any more — a tool is "something installed into
the guest, then surfaced on the dashboard". Four touch points:

**1. Install it inside the guest** — `flutter_app/lib/core/runtime.dart`.

- A distribution package: append it to the `apt-get install -y -qq --no-install-recommends …` list in
  phase 2 of `RuntimeBootstrap.run()`.
- A standalone tarball: follow the Node.js phase — put the version in `RuntimeSources`, add the
  per-architecture asset name to `DeviceArch`, download into `paths.downloads`, and extract inside the
  guest with an absolute path or via `/host-downloads/...`.
- Something heavy or optional: follow `installOllama()` — a separate method on `RuntimeBootstrap`,
  surfaced through `EnvironmentService` and run on a `TaskPage` so the user sees real log output.

**2. Teach the probe about it** — `flutter_app/lib/services/environment_service.dart`.
`EnvironmentService.probe()` answers "what is installed?" with one PRoot invocation that loops over

```sh
for t in node npm git python3 dsh openclaw ollama; do …
```

Add your command name to that list, otherwise the tool will always show as `missing`.

**3. Add it to the dashboard catalogue** — `flutter_app/lib/models/tool_status.dart`,
`ToolStatus.catalog()`. Fields: `id`, `name`, `description`, `icon`, and optionally
`dashboardUrl` (opens in the in-app WebView), `startCommand` (gives the card Start/Stop buttons) and
`optional: true` (gives it an **Install** button instead of Start). The summary card counts
`catalog().length`, so the "N of 6 tools ready" text updates itself.

**4. Wire the optional install, if any** — `flutter_app/lib/views/dashboard_view.dart` maps the
Ollama card's install action to a `TaskPage`. Add a branch for your tool the same way.

Then:

```bash
cd flutter_app
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```

Note that `flutter_app/test/widget_test.dart` asserts that the catalogue still contains
`dsh`, `openclaw`, `ollama`, `node`, `git` and `python3`. Adding tools is fine; removing or renaming
one requires updating that test.

---

## Signing

The workflow does **not** add a `key.properties` or a release keystore, and the repository contains
neither (`flutter_app/android/key.properties`, `flutter_app/android/release.keystore` and
`*.apk`/`*.aab` are in `.gitignore`). The APKs CI produces are therefore signed the way the
Flutter-generated project signs `--release` builds by default, which in current Flutter templates
falls back to the debug keystore. **Verify the signature before you distribute a build.**

To ship a properly signed APK:

1. Generate a keystore (keep it out of the repository):

   ```bash
   keytool -genkey -v -keystore release.keystore -alias termux-allinone \
     -keyalg RSA -keysize 2048 -validity 10000
   ```

2. Add the keystore and its passwords as repository secrets (base64-encode the keystore, then decode
   it in a workflow step).
3. **Inject the signing config in `patch_android.py`**, not by editing `flutter_app/android` by hand —
   the Android project is deleted and regenerated on every CI run. Read
   `android/key.properties` in a new patch function and rewrite the generated `signingConfigs` /
   `buildTypes.release` block, asserting that each substitution matched.

Because the app cannot be published on Google Play (`targetSdk 28`), signing only matters for
side-loading authenticity, not for store compliance.

---

## Release checklist

- [ ] Bump `version:` in `flutter_app/pubspec.yaml` (currently `1.0.2+3`).
- [ ] If a runtime version changed, update `RuntimeSources` / `DeviceArch` in
      `flutter_app/lib/core/runtime.dart` and handle the cached-archive gotchas above.
- [ ] Update the download table in `README.md` and `README.zh-CN.md` if versions, filenames or sizes
      changed.
- [ ] `cd flutter_app && flutter pub get`
- [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings` — clean.
- [ ] `flutter test` — green.
- [ ] Local release build succeeds for both `android-arm64` and `android-x64`.
- [ ] Scaffold + patch step still succeeds (i.e. `patch_android.py` did not trip an assertion).
- [ ] **Install the APK on a physical arm64 device and walk the first run, the Tools tab, the Console
      and `dsh web` end to end.** This is the step that has not yet been done for any release — do it
      before announcing, or keep the "not verified on a device" note in the READMEs.
- [ ] Tag and push: `git tag v1.0.2 && git push origin v1.0.2`.
- [ ] Confirm the GitHub Release contains exactly `termux-allinone-arm64.apk` and
      `termux-allinone-x86_64.apk`.
- [ ] Re-check that the READMEs still state the honest verification status and limitations.

---

## Build troubleshooting

**`flutter build apk` fails: "No Android SDK found" / missing platform**
Run `flutter doctor -v` and accept the licences (`flutter doctor --android-licenses`). The generated
project targets whatever platform your Flutter version expects.

**`android/` is missing, or the build fails with "no app/build.gradle(.kts) found"**
You skipped the scaffold step. CI always scaffolds before patching; do the same locally
([Build locally](#build-locally)). Do not run `flutter create` in place inside `flutter_app` —
it would infer the wrong organisation and project name.

**`patch_android.py` fails with `expected exactly one minSdk reference …, found 0`**
Flutter's generated Gradle file changed shape. Inspect
`flutter_app/android/app/build.gradle(.kts)` and update the regexes in
`.github/scripts/patch_android.py`. The assertion is there precisely so this is noticed.

**Gradle runs out of memory**
Add to `flutter_app/android/gradle.properties` (regenerated each build — for CI, inject it from
`patch_android.py`):

```properties
org.gradle.jvmargs=-Xmx4096m -Dkotlin.daemon.jvm.options="-Xmx2048m"
```

**`flutter analyze` fails on lints**
The workflow passes `--no-fatal-infos --no-fatal-warnings`; for a stricter local run drop those flags
and fix what it reports.

**`flutter test` fails on the catalogue test**
`widget_test.dart` asserts the tool ids `dsh`, `openclaw`, `ollama`, `node`, `git`, `python3` exist.
Update the test alongside `ToolStatus.catalog()`.

**The app installs but the first-run screen fails at a download**
That is a runtime issue, not a build issue — see the troubleshooting section of
[USER_GUIDE.md](USER_GUIDE.md#downloads-fail-or-stall).

**`adb install` refuses to overwrite an existing install**
The APK is signed differently from the installed one (for example you installed a CI build earlier).
Uninstall first — note that this deletes the whole runtime, including downloads and models.
