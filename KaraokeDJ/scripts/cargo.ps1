param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CargoArgs = @('run'))
$ErrorActionPreference = 'Stop'
# Git also ships link.exe; select the installed Microsoft toolchain explicitly.
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
if (Test-Path -LiteralPath $vswhere) {
    $installation = & $vswhere -latest -products '*' -property installationPath
    $toolset = Get-ChildItem "$installation/VC/Tools/MSVC" -Directory |
        Sort-Object Name -Descending |
        Where-Object { Test-Path -LiteralPath "$($_.FullName)/bin/Hostx64/x64/link.exe" } |
        Select-Object -First 1
    if ($toolset) {
        & "$installation/Common7/Tools/Launch-VsDevShell.ps1" -Arch amd64 -HostArch amd64 -SkipAutomaticLocation
        $env:PATH = "$($toolset.FullName)/bin/Hostx64/x64;$env:PATH"
        $env:LIB = "$($toolset.FullName)/lib/x64;$env:LIB"
        $env:INCLUDE = "$($toolset.FullName)/include;$env:INCLUDE"
    }
}
& cargo @CargoArgs
exit $LASTEXITCODE
