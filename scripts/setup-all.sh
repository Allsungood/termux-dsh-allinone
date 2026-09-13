#!/usr/bin/env bash
# ==============================================================================
# setup-all.sh — One-click setup for dsh, openclaw, and ollama environments.
#
# This orchestrates the individual setup scripts with proper ordering and
# progress reporting.
#
# Usage:
#   bash setup-all.sh            # interactive with prompts
#   bash setup-all.sh -y         # non-interactive (auto-yes)
#   USE_PREBUILT=0 bash setup-all.sh -y  # force source build for ollama
# ==============================================================================
set -euo pipefail

DSH_APPROVE_POLICY="${DSH_APPROVE_POLICY:-never}"
USE_PREBUILT="${USE_PREBUILT:-1}"

# Parse flags
AUTO_YES=0
while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes) AUTO_YES=1 ;;
        *) echo "Unknown option: $1" ;;
    esac
    shift
done

export DSH_ASSUME_YES=${AUTO_YES}

echo "==> [all] Starting one-click setup for dsh + openclaw + ollama"
echo "    Approval policy: ${DSH_APPROVE_POLICY}"
echo "    Auto-yes: ${AUTO_YES}"
echo ""

# ------------------------------------------------------------------------------
# 1. Setup dsh (DeepSeek Harness)
# ------------------------------------------------------------------------------
bash "${BASH_SOURCE%/*}/setup-dsh.sh" || {
    echo "!! dsh setup failed. Continuing anyway..."
}

echo ""
# ------------------------------------------------------------------------------
# 2. Setup openclaw
# ------------------------------------------------------------------------------
bash "${BASH_SOURCE%/*}/setup-openclaw.sh" || {
    echo "!! openclaw setup failed. Continuing anyway..."
}

echo ""
# ------------------------------------------------------------------------------
# 3. Setup ollama
# ------------------------------------------------------------------------------
bash "${BASH_SOURCE%/*}/setup-ollama.sh" || {
    echo "!! ollama setup failed. Continuing anyway..."
}

echo ""
echo "==> [all] Setup sequence completed!"
echo ""
echo "=== Usage Guide ==="
echo "dsh:     dsh web --port 3080     # DeepSeek Harness Web UI"
echo "openclaw: openclawx start        # OpenClaw AI Gateway"
echo "          openclawx onboarding   # Configure API keys"
echo "ollama:  ollama serve            # Start Ollama server"
echo "          ollama pull llama3.2:1b # Download a small model"
echo ""
echo "Tips:"
echo "  • First-time setup may take 2-5 minutes"
echo "  • Ollama models are stored in ~/.ollama/models or /sdcard/ollama-models"
echo "  • Disable battery optimization for best background performance"
echo ""