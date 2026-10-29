#!/usr/bin/env bash
# nvim.sh: Isolated Neovim environment launcher for Luex
# Directs configuration to ./nvim and data/cache to ./nvim-data

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

XDG_CONFIG_HOME="$SCRIPT_DIR" \
XDG_DATA_HOME="$SCRIPT_DIR/nvim-data/data" \
XDG_STATE_HOME="$SCRIPT_DIR/nvim-data/state" \
XDG_CACHE_HOME="$SCRIPT_DIR/nvim-data/cache" \
nvim "$@"
