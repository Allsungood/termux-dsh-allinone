#!/usr/bin/env bash
# ==============================================================================
# setup-dsh.sh — Configure and install dsh (DeepSeek Harness) on Termux.
#
# This script:
#   1. Installs glibc + glibc-runner (required for running official Node.js)
#   2. Installs the dsh-termux runtime (Node.js + patched dsh + updater)
#   3. Sets the approval policy to "never" (for automated execution)
#   4. Configures the web UI to start on port 3080
#
# Usage:
#   bash setup-dsh.sh
#   DSH_APPROVE_POLICY=never bash setup-dsh.sh   # default
#   DSH_APPROVE_POLICY=ask bash setup-dsh.sh      # manual approval mode
# ==============================================================================
set -euo pipefail

DSH_APPROVE_POLICY="${DSH_APPROVE_POLICY:-never}"
DSH_WEB_PORT="${DSH_WEB_PORT:-3080}"

echo "==> [dsh] Setting up DeepSeek Harness environment"

# ------------------------------------------------------------------------------
# 1. Install glibc (if not already installed)
# ------------------------------------------------------------------------------
if ! command -v grun >/dev/null 2>&1; then
    echo "    Installing glibc packages..."
    pkg update
    pkg install -y glibc-repo
    pkg install -y glibc glibc-runner
else
    echo "    glibc already installed."
fi

# ------------------------------------------------------------------------------
# 2. Install dsh-termux runtime
# ------------------------------------------------------------------------------
if ! command -v dsh >/dev/null 2>&1; then
    echo "    Installing dsh-termux runtime..."
    curl -fsSL https://github.com/ErEbusE/dsh-termux/releases/latest/download/install.sh | bash -s -- -y
else
    echo "    dsh already installed. Updating..."
    dsh update -t next -y
fi

# ------------------------------------------------------------------------------
# 3. Configure approval policy
# ------------------------------------------------------------------------------
echo "    Setting approval policy to: ${DSH_APPROVE_POLICY}"
mkdir -p ~/.dsh
cat > ~/.dsh/config.json << EOF
{
  "approvalPolicy": "${DSH_APPROVE_POLICY}",
  "webPort": ${DSH_WEB_PORT},
  "autoStart": true
}
EOF

# ------------------------------------------------------------------------------
# 4. Verify installation
# ------------------------------------------------------------------------------
echo "    Verifying dsh installation..."
dsh --version

echo "==> [dsh] Setup complete!"
echo "    Start web UI:  dsh web --port ${DSH_WEB_PORT}"
echo "    Update dsh:    dsh update -t next -y"