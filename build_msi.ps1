<#
.SYNOPSIS
  Genera el instalador MSI (por usuario, sin administrador) en dist\my-jira-work-time-<version>.msi.

.DESCRIPTION
  Necesita la compilacion release (la crea con build_windows.ps1 si falta o con -Build)
  y WiX 5:  dotnet tool install --global wix --version 5.0.2
  La version sale de pubspec.yaml (sin el +build).

.EXAMPLE
  .\build_msi.ps1 -Build
#>
param([switch]$Build)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$release = Join-Path $root 'build\windows\x64\runner\Release'

if ($Build -or -not (Test-Path (Join-Path $release 'gestion_time_proyect.exe'))) {
  & (Join-Path $root 'build_windows.ps1')
  if ($LASTEXITCODE -ne 0) { throw 'Fallo la compilacion de Windows' }
}
if (-not (Get-Command wix -ErrorAction SilentlyContinue)) {
  throw 'Falta WiX: dotnet tool install --global wix --version 5.0.2'
}

$version = (Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(\d+\.\d+\.\d+)').Matches[0].Groups[1].Value
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$msi = Join-Path $dist "my-jira-work-time-$version.msi"

wix build (Join-Path $root 'tool\installer\Package.wxs') `
  -d "Src=$release" -d "Version=$version" `
  -d "Icon=$(Join-Path $root 'windows\runner\resources\app_icon.ico')" `
  -arch x64 -o $msi
if ($LASTEXITCODE -ne 0) { throw 'Fallo wix build' }
Write-Host "MSI: $msi"
