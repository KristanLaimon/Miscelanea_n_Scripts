<#
.SYNOPSIS
Fast installation launcher script for demo client environment (.\nvim).

.DESCRIPTION
Executes luex/install.ps1 to deploy the Luex framework engine directly into .\nvim\.luelte\core.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\install.ps1
#>
[CmdletBinding()]
param (
    [Parameter(Position = 0, Mandatory = $false)]
    [string]$TargetDir = ".\nvim"
)

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$installerPath = Join-Path $scriptDir "luex\install.ps1"

& powershell -ExecutionPolicy Bypass -File $installerPath -TargetDir $TargetDir
