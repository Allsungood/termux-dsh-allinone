#!/usr/bin/env bash
# ==============================================================================
# setup-openclaw.sh — Configure and install OpenClaw AI Gateway on Termux.
#
# This script installs OpenClaw using the approach from the mithun50/openclaw-termux
# project, adapted for integration with our all-in-one Termux bootstrap.
#
# Usage:
#   bash setup-openclaw.sh
#   OPENCLAW_VERSION=v1.8.7 bash setup-openclaw.sh
# ==============================================================================
set -euo pipefail

OPENCLAW_VERSION="${OPENCLAW_VERSION:-v1.8.7}"
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"

echo "==> [openclaw] Setting up OpenClaw AI Gateway"

# ------------------------------------------------------------------------------
# 1. Install proot-distro and Ubuntu (if not already installed)
# ------------------------------------------------------------------------------
if ! command -v proot-distro >/dev/null 2>&1; then
    echo "    Installing proot-distro..."
    pkg install -y proot-distro
fi

# Install Ubuntu if not already installed
if ! proot-distro list | grep -q "ubuntu"; then
    echo "    Installing Ubuntu..."
    proot-distro install ubuntu
fi

# ------------------------------------------------------------------------------
# 2. Configure OpenClaw inside Ubuntu
# ------------------------------------------------------------------------------
echo "    Configuring OpenClaw in Ubuntu environment..."

proot-distro login ubuntu << 'OS_INSTALL_EOF'
set -e

# Install curl if not present
apt-get update
apt-get install -y curl

# Install Node.js 22 via NodeSource
if ! command -v node >/dev/null 2>&1; then
    echo "    Installing Node.js 22..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
fi

# Install OpenClaw globally
if ! command -v openclaw >/dev/null 2>&1; then
    echo "    Installing OpenClaw..."
    npm install -g openclaw
fi

# --- Bionic Bypass ---
# Android's Bionic libc causes os.networkInterfaces() to crash on some devices.
# This monkey-patch provides a fallback.
mkdir -p ~/.openclaw
cat > ~/.openclaw/bionic-bypass.js << 'BYPASS_EOF'
const os = require('os');
const originalNetworkInterfaces = os.networkInterfaces;
os.networkInterfaces = function() {
  try {
    const interfaces = originalNetworkInterfaces.call(os);
    if (interfaces && Object.keys(interfaces).length > 0) {
      return interfaces;
    }
  } catch (e) {}
  return {
    lo: [{
      address: '127.0.0.1',
      netmask: '255.0.0.0',
      family: 'IPv4',
      mac: '00:00:00:00:00:00',
      internal: true,
      cidr: '127.0.0.1/8'
    }]
  };
};
BYPASS_EOF

# Add NODE_OPTIONS to bashrc
if ! grep -q "bionic-bypass" ~/.bashrc; then
    echo 'export NODE_OPTIONS="--require ~/.openclaw/bionic-bypass.js"' >> ~/.bashrc
fi

# --- Configure OpenClaw ---
mkdir -p ~/.openclaw

cat > ~/.openclaw/openclaw.json << CONFIG_EOF
{
    "port": ${OPENCLAW_PORT},
    "host": "127.0.0.1",
    "log_level": "info"
}
CONFIG_EOF

echo "OpenClaw installed successfully!"
OS_INSTALL_EOF

# ------------------------------------------------------------------------------
# 3. Create wrapper script for Termux-side access
# ------------------------------------------------------------------------------
WRAPPER_SCRIPT="${HOME}/.local/bin/openclawx"
mkdir -p "${HOME}/.local/bin"
cat > "${WRAPPER_SCRIPT}" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# OpenClaw wrapper — routes commands to the Ubuntu proot environment
exec proot-distro login ubuntu --shared-tmp -- bash -c "
    export NODE_OPTIONS='--require ~/.openclaw/bionic-bypass.js'
    openclaw \$@
"
EOF
chmod +x "${WRAPPER_SCRIPT}"

# ------------------------------------------------------------------------------
# 4. Verify
# ------------------------------------------------------------------------------
echo "    Verifying OpenClaw installation..."
"${WRAPPER_SCRIPT}" --version || echo "    (OpenClaw may need first-time onboarding)"

echo "==> [openclaw] Setup complete!"
echo "    Run onboarding: openclawx onboarding"
echo "    Start gateway:  openclawx start"
echo "    Web dashboard:  http://localhost:${OPENCLAW_PORT}"