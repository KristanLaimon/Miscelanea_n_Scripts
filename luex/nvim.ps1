<#
.SYNOPSIS
Inicia Neovim de forma 100% portátil.
La configuración se lee de ./nvim y todos los plugins/datos se guardan en ./nvim-data
#>

# 1. Guardar el estado actual de las variables globales
$OldConfig = $env:XDG_CONFIG_HOME
$OldData   = $env:XDG_DATA_HOME
$OldState  = $env:XDG_STATE_HOME
$OldCache  = $env:XDG_CACHE_HOME

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$DataDir   = Join-Path $ScriptDir "nvim-data"

try {
    # 2. Configurar la ruta de configuración (Neovim buscará 'init.lua' en $ScriptDir/nvim/)
    $env:XDG_CONFIG_HOME = $ScriptDir
    
    # 3. Redirigir plugins, historial y caché a la carpeta hermana ./nvim-data/
    # Neovim creará subcarpetas internamente aquí sin tocar tu carpeta de configuración
    $env:XDG_DATA_HOME  = Join-Path $DataDir "data"
    $env:XDG_STATE_HOME = Join-Path $DataDir "state"
    $env:XDG_CACHE_HOME = Join-Path $DataDir "cache"

    # 4. Ejecutar Neovim pasando cualquier argumento adicional (ej. archivos a abrir)
    & nvim $args
}
finally {
    # 5. Restaurar las variables de entorno originales al cerrar el editor
    if ($null -ne $OldConfig) { $env:XDG_CONFIG_HOME = $OldConfig } else { Remove-Item Env:\XDG_CONFIG_HOME -ErrorAction SilentlyContinue }
    if ($null -ne $OldData)   { $env:XDG_DATA_HOME = $OldData }     else { Remove-Item Env:\XDG_DATA_HOME -ErrorAction SilentlyContinue }
    if ($null -ne $OldState)  { $env:XDG_STATE_HOME = $OldState }   else { Remove-Item Env:\XDG_STATE_HOME -ErrorAction SilentlyContinue }
    if ($null -ne $OldCache)  { $env:XDG_CACHE_HOME = $OldCache }   else { Remove-Item Env:\XDG_CACHE_HOME -ErrorAction SilentlyContinue }
}