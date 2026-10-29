#!/usr/bin/env bash
# ==============================================================================
# Luex Framework Engine Installer for Linux/macOS
# ==============================================================================
# Description:
#   Deploys core framework files (init.lua, compiler.lua, runtime.lua, builder.lua,
#   testing.lua, syntax/) from luex/core into the target Neovim configuration's
#   .luelte/core directory.
#
# Usage:
#   ./install.sh <TARGET_DIR>
#
# Arguments:
#   TARGET_DIR  Mandatory destination directory for Neovim config (or its .luelte/core path).
#
# Examples:
#   ./install.sh /path/to/custom_nvim
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/core"

RAW_TARGET="${1:-}"

if [ -z "$RAW_TARGET" ]; then
    echo -e "\033[0;31mError: TARGET_DIR parameter is mandatory.\033[0m"
    echo -e "Usage: ./install.sh <path/to/target_nvim>"
    exit 1
fi

if [[ "$RAW_TARGET" == *".luelte/core"* ]]; then
    TARGET_CORE="$RAW_TARGET"
else
    TARGET_CORE="$RAW_TARGET/.luelte/core"
fi

echo -e "\033[0;36mInstalling Luex Framework Engine into Neovim environment...\033[0m"
echo -e "\033[0;90mSource: $SOURCE_DIR\033[0m"
echo -e "\033[0;90mTarget: $TARGET_CORE\033[0m"

mkdir -p "$TARGET_CORE"
cp -r "$SOURCE_DIR/"* "$TARGET_CORE/"

echo -e "\033[0;32mLuex Framework Engine successfully installed into $TARGET_CORE!\033[0m"
