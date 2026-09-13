#!/usr/bin/env bash
# ==============================================================================
# make-bootstrap.sh — Build a custom Termux bootstrap tarball with pre-installed
# packages defined in packages.txt.
#
# Usage:
#   bash make-bootstrap.sh                        # default: aarch64
#   ARCH=arm bash make-bootstrap.sh               # 32-bit arm (armeabi-v7a)
#   ARCH=x86_64 bash make-bootstrap.sh            # x86_64 (emulator)
#
# Output:
#   ../bootstrap-<arch>.zip — ready to be dropped into termux-app's assets or
#   served by a custom bootstrap server.
# ==============================================================================
set -euo pipefail

ARCH="${ARCH:-aarch64}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PACKAGES_FILE="${SCRIPT_DIR}/packages.txt"
OUTPUT_DIR="${ROOT_DIR}/out"
OUTPUT_FILE="${OUTPUT_DIR}/bootstrap-${ARCH}.zip"

# Official Termux bootstrap URL pattern (Termux releases host these on GitHub).
# Override with BOOTSTRAP_BASE_URL if you use a custom bootstrap server.
BOOTSTRAP_BASE_URL="${BOOTSTRAP_BASE_URL:-https://github.com/termux/termux-app/releases/download/bootstrap-20240907}"

echo "==> Building custom Termux bootstrap for ${ARCH}"
echo "    Packages file: ${PACKAGES_FILE}"
echo "    Output: ${OUTPUT_FILE}"

# ------------------------------------------------------------------------------
# 1. Prepare a clean working directory
# ------------------------------------------------------------------------------
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/termux-bootstrap.XXXXXX")"
echo "    Work dir: ${WORK_DIR}"
trap 'rm -rf "${WORK_DIR}"' EXIT

mkdir -p "${WORK_DIR}/rootfs" "${OUTPUT_DIR}"

# ------------------------------------------------------------------------------
# 2. Download and extract the official Termux bootstrap
# ------------------------------------------------------------------------------
BOOTSTRAP_URL="${BOOTSTRAP_BASE_URL}/bootstrap-${ARCH}.zip"
echo "==> Downloading official bootstrap: ${BOOTSTRAP_URL}"
curl -fL --retry 3 --retry-delay 2 -o "${WORK_DIR}/bootstrap.zip" "${BOOTSTRAP_URL}"
unzip -q "${WORK_DIR}/bootstrap.zip" -d "${WORK_DIR}/rootfs"

# The official bootstrap is a minimal Alpine rootfs with Termux's /usr layout.
PREFIX="${WORK_DIR}/rootfs"

# ------------------------------------------------------------------------------
# 3. Install additional packages using proot + apk (Alpine package manager)
# ------------------------------------------------------------------------------
echo "==> Installing extra packages via proot..."

if ! command -v proot >/dev/null 2>&1; then
    echo "    Installing proot..."
    if command -v apt >/dev/null 2>&1; then
        apt update && apt install -y proot
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y proot
    elif command -v pacman >/dev/null 2>&1; then
        pacman -S --noconfirm proot
    else
        echo "!! Cannot install proot automatically. Please install it manually."
        exit 1
    fi
fi

cat > "${WORK_DIR}/install-packages.sh" << 'INSTALL_EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PACKAGES_FILE="/packages.txt"

# Update package lists
apk update

# Read packages from file (skip comments and empty lines)
while IFS= read -r line; do
    line="$(echo "${line}" | sed 's/#.*//' | xargs)"  # strip comments and trim
    [ -z "${line}" ] && continue

    # Parse optional version pin
    if [[ "${line}" == *:* ]]; then
        PKG="${line%%:*}"
        VER="${line#*:}"
        echo "    Installing ${PKG}=${VER}..."
        apk add --no-cache "${PKG}=${VER}" || {
            echo "!! Failed to install ${PKG}=${VER}, trying without version pin"
            apk add --no-cache "${PKG}"
        }
    else
        PKG="${line}"
        echo "    Installing ${PKG}..."
        apk add --no-cache "${PKG}"
    fi
done < "${PACKAGES_FILE}"

# Clean up apk cache to reduce size
apk clean
INSTALL_EOF

chmod +x "${WORK_DIR}/install-packages.sh"

# Copy packages.txt into the rootfs
cp "${PACKAGES_FILE}" "${WORK_DIR}/rootfs/packages.txt"

# Execute installation inside proot
proot \
    --rootfs="${PREFIX}" \
    --root-id \
    --kill-on-exit \
    --bind=/proc:/proc \
    --bind=/sys:/sys \
    --bind=/dev:/dev \
    --link2symlink \
    -b "${WORK_DIR}/install-packages.sh:/install-packages.sh" \
    -b "${WORK_DIR}/rootfs/packages.txt:/packages.txt" \
    -w /data/data/com.termux/files/usr \
    /data/data/com.termux/files/usr/bin/bash /install-packages.sh

# ------------------------------------------------------------------------------
# 4. Create the final bootstrap zip
# ------------------------------------------------------------------------------
echo "==> Creating bootstrap zip: ${OUTPUT_FILE}"
cd "${WORK_DIR}/rootfs"
zip -qr "${OUTPUT_FILE}" .
cd - >/dev/null

echo "==> Done!"
echo "    Bootstrap size: $(du -h "${OUTPUT_FILE}" | cut -f1)"
echo "    Output: ${OUTPUT_FILE}"
echo ""
echo "To use this bootstrap in the Flutter app:"
echo "  1. Place ${OUTPUT_FILE} in flutter_app/android/app/src/main/assets/"
echo "  2. Or serve it from a custom bootstrap server URL"