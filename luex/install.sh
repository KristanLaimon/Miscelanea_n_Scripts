#!/usr/bin/env bash
# ==============================================================================
# Fast Installation Launcher Script for Demo Client Environment (./nvim)
# ==============================================================================
# Executes ./luex/install.sh to deploy the Luex framework engine directly into ./nvim/.luelte/core.
#
# Usage:
#   ./install.sh [TARGET_DIR]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-$SCRIPT_DIR/nvim}"

chmod +x "$SCRIPT_DIR/luex/install.sh"
"$SCRIPT_DIR/luex/install.sh" "$TARGET_DIR"
