<#
.SYNOPSIS
Launches a 100% isolated Neovim testing environment for Luex repository.
Configuration is read from ./nvim and data is stored in ./nvim-data.
#>

$OldConfig = $env:XDG_CONFIG_HOME
$OldData   = $env:XDG_DATA_HOME
$OldState  = $env:XDG_STATE_HOME
$OldCache  = $env:XDG_CACHE_HOME

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$DataDir   = Join-Path $ScriptDir "nvim-data"

try {
    # Direct Neovim configuration to $ScriptDir/nvim/ init.lua
    $env:XDG_CONFIG_HOME = $ScriptDir
    
    # Direct data, state and cache to ./nvim-data/
    $env:XDG_DATA_HOME  = Join-Path $DataDir "data"
    $env:XDG_STATE_HOME = Join-Path $DataDir "state"
    $env:XDG_CACHE_HOME = Join-Path $DataDir "cache"

    & nvim $args
}
finally {
    # Restore environment variables upon exit
    if ($null -ne $OldConfig) { $env:XDG_CONFIG_HOME = $OldConfig } else { Remove-Item Env:\XDG_CONFIG_HOME -ErrorAction SilentlyContinue }
    if ($null -ne $OldData)   { $env:XDG_DATA_HOME = $OldData }     else { Remove-Item Env:\XDG_DATA_HOME -ErrorAction SilentlyContinue }
    if ($null -ne $OldState)  { $env:XDG_STATE_HOME = $OldState }   else { Remove-Item Env:\XDG_STATE_HOME -ErrorAction SilentlyContinue }
    if ($null -ne $OldCache)  { $env:XDG_CACHE_HOME = $OldCache }   else { Remove-Item Env:\XDG_CACHE_HOME -ErrorAction SilentlyContinue }
}
