<#
.SYNOPSIS
Installs the Luex Framework Engine into a target Neovim configuration environment.

.DESCRIPTION
Deploys core framework files (init.lua, compiler.lua, runtime.lua, builder.lua, testing.lua, syntax/)
from luex/core into the target Neovim configuration's .luelte/core directory.

.PARAMETER TargetDir
Mandatory. The target Neovim configuration directory (or its .luelte/core path).

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\luex\install.ps1 -TargetDir "C:\path\to\nvim"
Installs Luex into target Neovim configuration directory.
#>
[CmdletBinding()]
param (
    [Parameter(Position = 0, Mandatory = $false)]
    [string]$TargetDir
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($TargetDir)) {
    Write-Error "Error: TargetDir parameter is mandatory. Usage: .\install.ps1 -TargetDir <path\to\nvim>"
    exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceDir = Join-Path $scriptDir "core"

if ($TargetDir.EndsWith(".luelte\core") -or $TargetDir.EndsWith(".luelte/core")) {
    $targetCoreDir = $TargetDir
} else {
    $targetCoreDir = Join-Path $TargetDir ".luelte\core"
}

Write-Host "Installing Luex Framework Engine into Neovim environment..." -ForegroundColor Cyan
Write-Host "Source: $sourceDir" -ForegroundColor Gray
Write-Host "Target: $targetCoreDir" -ForegroundColor Gray

if (-not (Test-Path $targetCoreDir)) {
    New-Item -ItemType Directory -Path $targetCoreDir -Force | Out-Null
}

Copy-Item -Path "$sourceDir\*" -Destination $targetCoreDir -Recurse -Force

Write-Host "Luex Framework Engine successfully installed into $targetCoreDir!" -ForegroundColor Green
