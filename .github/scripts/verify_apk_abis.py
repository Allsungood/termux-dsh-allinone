#!/usr/bin/env python3
"""Assert each staged APK carries native libraries for exactly one ABI.

Why this guard exists: `flutter build apk --target-platform android-arm64`
packages plugin AAR native libraries for *every* ABI while the Flutter engine
libraries (``libflutter.so`` / ``libapp.so``) only exist for the requested one.
Such an APK contains a populated ``lib/armeabi-v7a/`` or ``lib/x86_64/``
directory, so Android happily installs it on a device the engine was never
built for — and the app then dies on startup instead of being reported as
incompatible. Building with ``--split-per-abi`` produces properly filtered
APKs, and this script proves it stayed that way.
"""

from __future__ import annotations

import pathlib
import sys
import zipfile

# Staged APK filename -> the single ABI it must contain
EXPECTED: dict[str, str] = {
    "termux-allinone-arm64.apk": "arm64-v8a",
    "termux-allinone-x86_64.apk": "x86_64",
}

ROOT = pathlib.Path(__file__).resolve().parents[2]


def check(name: str, abi: str) -> bool:
    path = ROOT / name
    if not path.is_file():
        print(f"::error::missing staged APK: {name}")
        return False

    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        found = {
            entry.split("/")[1]
            for entry in names
            if entry.startswith("lib/") and entry.count("/") >= 2
        }
        engine = f"lib/{abi}/libflutter.so"
        app = f"lib/{abi}/libapp.so"
        has_engine = engine in names
        has_app = app in names

    ok = True
    if found != {abi}:
        print(
            f"::error::{name}: expected only ABI '{abi}' but found "
            f"{sorted(found) or 'no native libraries'}"
        )
        ok = False
    if not has_engine:
        print(f"::error::{name}: {engine} is missing")
        ok = False
    if not has_app:
        print(f"::error::{name}: {app} is missing")
        ok = False
    if ok:
        print(f"OK {name}: ABI={abi}, {engine} and {app} both present")
    return ok


def main() -> None:
    results = [check(name, abi) for name, abi in EXPECTED.items()]
    if not all(results):
        raise SystemExit(1)
    print("All staged APKs are ABI-consistent.")


if __name__ == "__main__":
    main()
