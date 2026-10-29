#!/usr/bin/env bash
# nvim-portable.sh
# Inicia Neovim aislando la configuración en ./nvim y los datos en ./nvim-data

# Las variables definidas antes del comando 'nvim' solo existen para esa instancia
XDG_CONFIG_HOME="$PWD" \
XDG_DATA_HOME="$PWD/nvim-data/data" \
XDG_STATE_HOME="$PWD/nvim-data/state" \
XDG_CACHE_HOME="$PWD/nvim-data/cache" \
nvim "$@"