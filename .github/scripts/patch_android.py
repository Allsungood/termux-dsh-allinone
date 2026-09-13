#!/usr/bin/env python3
"""Patch the Flutter-generated Android project for this app.

The generated project cannot know two things this app depends on:

1. ``targetSdk`` must stay below 29 (and ``minSdk`` at 24).

   Android 10 (API 29) introduced a W^X restriction: an app whose ``targetSdk``
   is 29 or higher may no longer ``execve`` a file it wrote into its own data
   directory. This app's entire purpose is to execute PRoot and the binaries of
   a Linux root filesystem that it unpacked into its private storage, so the
   restriction would break it completely. Termux pins a low ``targetSdk`` for
   exactly the same reason. This build is distributed by side-loading only, so
   the Play Store's higher ``targetSdk`` requirement does not apply.

2. The manifest needs a display name, cleartext HTTP for the loopback
   dashboards (Android 9+ blocks cleartext by default), and the permissions the
   runtime relies on.

Every substitution is asserted, so a change in Flutter's generated project
fails this build loudly instead of silently producing a broken APK.
"""

from __future__ import annotations

import pathlib
import re
import sys

APP_LABEL = "Termux All-in-One"
MIN_SDK = "24"
TARGET_SDK = "28"

PERMISSIONS = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.WAKE_LOCK",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.WRITE_EXTERNAL_STORAGE",
]

ROOT = pathlib.Path(__file__).resolve().parents[2]
ANDROID = ROOT / "flutter_app" / "android"


def fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)
    raise SystemExit(1)


def patch_gradle() -> None:
    candidates = [
        ANDROID / "app" / "build.gradle.kts",
        ANDROID / "app" / "build.gradle",
    ]
    path = next((c for c in candidates if c.is_file()), None)
    if path is None:
        fail("no app/build.gradle(.kts) found — did `flutter create` run first?")

    text = path.read_text(encoding="utf-8")
    original = text
    kotlin_dsl = path.suffix == ".kts"

    # Handles both `minSdk = flutter.minSdkVersion` (Kotlin DSL) and
    # `minSdkVersion flutter.minSdkVersion` (Groovy DSL).
    text, min_hits = re.subn(
        r"(minSdk(?:Version)?\s*=?\s*)flutter\.minSdkVersion",
        rf"\g<1>{MIN_SDK}",
        text,
    )
    text, target_hits = re.subn(
        r"(targetSdk(?:Version)?\s*=?\s*)flutter\.targetSdkVersion",
        rf"\g<1>{TARGET_SDK}",
        text,
    )

    if min_hits != 1:
        fail(f"expected exactly one minSdk reference in {path}, found {min_hits}")
    if target_hits != 1:
        fail(
            f"expected exactly one targetSdk reference in {path}, "
            f"found {target_hits}"
        )

    # The deliberate low targetSdk trips AGP's `ExpiredTargetSdkVersion` check,
    # which is fatal for release builds. It is advisory Play-Store policy and
    # does not apply to a side-loaded app, so the check is switched off here.
    if "ExpiredTargetSdkVersion" not in text:
        if kotlin_dsl:
            lint_block = (
                "\n    lint {\n"
                "        checkReleaseBuilds = false\n"
                '        disable.add("ExpiredTargetSdkVersion")\n'
                "    }\n"
            )
        else:
            lint_block = (
                "\n    lint {\n"
                "        checkReleaseBuilds false\n"
                "        disable 'ExpiredTargetSdkVersion'\n"
                "    }\n"
            )
        text, lint_hits = re.subn(r"(android\s*\{)", rf"\1{lint_block}", text, count=1)
        if lint_hits != 1:
            fail(f"could not insert a lint block into {path}")

    if text == original:
        fail(f"{path} was not modified")

    path.write_text(text, encoding="utf-8")
    print(
        f"patched {path.relative_to(ROOT)}: minSdk={MIN_SDK} "
        f"targetSdk={TARGET_SDK}, ExpiredTargetSdkVersion disabled"
    )


def patch_manifest() -> None:
    path = ANDROID / "app" / "src" / "main" / "AndroidManifest.xml"
    if not path.is_file():
        fail(f"manifest not found at {path}")

    text = path.read_text(encoding="utf-8")
    original = text

    # 1. Display name.
    text, label_hits = re.subn(
        r'android:label="[^"]*"',
        f'android:label="{APP_LABEL}"',
        text,
        count=1,
    )
    if label_hits != 1:
        fail(f"could not set android:label in {path}")

    # 2. Cleartext HTTP for http://127.0.0.1:<port> dashboards.
    if "usesCleartextTraffic" not in text:
        text, cleartext_hits = re.subn(
            r"(<application\b)",
            r'\1\n        android:usesCleartextTraffic="true"',
            text,
            count=1,
        )
        if cleartext_hits != 1:
            fail(f"could not enable cleartext traffic in {path}")

    # 3. Permissions the runtime needs.
    missing = [p for p in PERMISSIONS if f'"{p}"' not in text]
    if missing:
        block = "\n".join(
            f'    <uses-permission android:name="{p}" />' for p in missing
        )
        text, perm_hits = re.subn(
            r"(<application\b)",
            f"{block}\n\n    \\1",
            text,
            count=1,
        )
        if perm_hits != 1:
            fail(f"could not insert permissions into {path}")

    if text == original:
        fail(f"{path} was not modified")

    path.write_text(text, encoding="utf-8")
    print(
        f"patched {path.relative_to(ROOT)}: label, cleartext traffic, "
        f"{len(PERMISSIONS)} permissions"
    )


def main() -> None:
    if not ANDROID.is_dir():
        fail(f"{ANDROID} does not exist — scaffold the Android platform first")
    patch_gradle()
    patch_manifest()
    print("Android project patched successfully.")


if __name__ == "__main__":
    main()
