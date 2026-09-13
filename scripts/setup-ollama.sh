#!/usr/bin/env bash
# ==============================================================================
# setup-ollama.sh — Install Ollama CLI and configure for Termux.
#
# Note: The full ollama binary with Vulkan GPU acceleration (llamux) requires
# compiling from source with Android NDK. This script installs the CLI wrapper
# and prepares the environment for either:
#   A) Prebuilt ollama binary (if available for arm64)
#   B) Source build (requires NDK and longer build time)
#
# Usage:
#   bash setup-ollama.sh
#   USE_PREBUILT=1 bash setup-ollama.sh  # Try prebuilt binary first
# ==============================================================================
set -euo pipefail

USE_PREBUILT="${USE_PREBUILT:-1}"
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.2:1b}"

echo "==> [ollama] Setting up Ollama for Termux"

# ------------------------------------------------------------------------------
# 1. Try prebuilt binary (fast path)
# ------------------------------------------------------------------------------
if [ "${USE_PREBUILT}" = "1" ]; then
    echo "    Checking for prebuilt ollama binary..."

    # Try to download the latest ollama binary for Linux arm64
    # Note: ollama's official releases provide linux-amd64; for arm64 Android,
    # we use the llamux project or a Termux-specific build.
    OLLAMA_BIN_DIR="${HOME}/.local/bin"
    mkdir -p "${OLLAMA_BIN_DIR}"

    # Try to fetch from ollama-termux project releases
    OLLAMA_URL="https://github.com/DioNanos/ollama-termux/releases/latest/download/ollama-linux-arm64"

    if curl -fsL --retry 2 --retry-delay 2 -o "${OLLAMA_BIN_DIR}/ollama" "${OLLAMA_URL}" 2>/dev/null; then
        chmod +x "${OLLAMA_BIN_DIR}/ollama"
        echo "    Prebuilt ollama binary installed."
    else
        echo "    No prebuilt binary available. Falling back to package install..."
        # Try Termux package manager
        if command -v apt >/dev/null 2>&1; then
            apt update && apt install -y ollama || true
        elif pkg update; then
            pkg install -y ollama 2>/dev/null || true
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 2. Install ollama CLI wrapper (npm package) as fallback
# ------------------------------------------------------------------------------
if ! command -v ollama >/dev/null 2>&1; then
    echo "    Installing ollama CLI via npm..."
    npm install -g ollama || echo "    (npm install failed — will use binary directly)"
fi

# ------------------------------------------------------------------------------
# 3. Configure ollama environment
# ------------------------------------------------------------------------------
mkdir -p ~/.ollama

# Set default model
cat > ~/.ollama/config << EOF
model: ${OLLAMA_MODEL}
host: 127.0.0.1:11434
EOF

# ------------------------------------------------------------------------------
# 4. Create wrapper for Android-specific paths
# ------------------------------------------------------------------------------
cat > "${HOME}/.local/bin/ollama-termux" << 'WRAPPER_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Ollama Termux wrapper — handles Android-specific paths and permissions

# Ensure storage access is available
if [ -d /sdcard ]; then
    export OLLAMA_MODELS="/sdcard/ollama-models"
else
    export OLLAMA_MODELS="${HOME}/.ollama/models"
fi
mkdir -p "${OLLAMA_MODELS}"

# Pass through to the real ollama binary
exec ollama "$@"
WRAPPER_EOF
chmod +x "${HOME}/.local/bin/ollama-termux"

# ------------------------------------------------------------------------------
# 5. Prepare model download (optional — not pre-loading to save space)
# ------------------------------------------------------------------------------
if [ -x "${HOME}/.local/bin/ollama" ] || command -v ollama >/dev/null 2>&1; then
    echo "    Ollama binary available."
    echo "    To download a model: ollama pull ${OLLAMA_MODEL}"
else
    echo "!! Ollama binary not found. Please install manually or build from source."
    echo "    See: https://github.com/DioNanos/ollama-termux"
fi

echo "==> [ollama] Setup complete!"
echo "    Binary: $(command -v ollama || echo 'not in PATH — check ~/.local/bin')"
echo "    Models: ollama list"
echo "    Run:    ollama serve (start server)"
echo "    Pull:   ollama pull ${OLLAMA_MODEL}"