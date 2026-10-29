$ErrorActionPreference = 'Stop'
$msvc = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft Visual Studio\*\*\VC\Tools\MSVC\*\bin\Hostx64\x64\link.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
$sdk = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\Lib" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
if (-not $msvc -or -not $sdk) { throw 'Install Visual Studio C++ Build Tools and the Windows SDK to build ClickProofer.' }
$toolchain = $msvc.Directory.Parent.Parent.Parent.FullName
$env:Path = "$($msvc.Directory.FullName);$env:Path"
$env:LIB = "$toolchain\lib\x64;$($sdk.FullName)\um\x64;$($sdk.FullName)\ucrt\x64"
Push-Location $PSScriptRoot
try {
    cargo test --locked
    if ($LASTEXITCODE -ne 0) { throw 'Rust tests failed.' }
    cargo build --release --locked
    if ($LASTEXITCODE -ne 0) { throw 'Rust build failed.' }
    Write-Host "Ready: $PSScriptRoot\target\release\clickproofer.exe"
} finally { Pop-Location }
