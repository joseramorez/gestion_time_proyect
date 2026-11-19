<#
.SYNOPSIS
  Compila la app para Windows en modo release.

.DESCRIPTION
  Ejecuta `flutter pub get` y `tool\flutter_env.ps1 build windows --release` (que anade las
  credenciales de Jira de `.env` solo si ese archivo existe). Al terminar muestra donde
  quedo la app. Hay que distribuir TODA la carpeta Release, no solo el .exe.

  -Verify   antes de compilar corre `flutter analyze` y `flutter test` (se detiene si fallan).
  -Zip      al final deja un .zip listo para entregar en dist\my-jira-work-time-windows.zip.

.EXAMPLE
  .\build_windows.ps1
  .\build_windows.ps1 -Verify -Zip

  Para ver los comandos sin ejecutarlos:  $env:DRY_RUN = '1'
#>
param(
  [switch]$Verify,
  [switch]$Zip
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$flutterEnv = Join-Path $root 'tool\flutter_env.ps1'
$release = Join-Path $root 'build\windows\x64\runner\Release'
$dryRun = $env:DRY_RUN -eq '1'

function Step([string]$title, [scriptblock]$action) {
  Write-Host "==> $title" -ForegroundColor Cyan
  if ($dryRun) { Write-Host "    (DRY_RUN) $($action.ToString().Trim())"; return }
  & $action
  if ($LASTEXITCODE -ne 0) { throw "Fallo: $title (codigo $LASTEXITCODE)" }
}

# Una app abierta bloquea el .exe y la compilacion falla al reemplazarlo.
if (-not $dryRun -and (Get-Process gestion_time_proyect -ErrorAction SilentlyContinue)) {
  Write-Warning 'La app esta abierta y puede bloquear el .exe: cierrala antes de compilar.'
}

Push-Location $root
try {
  Step 'flutter pub get' { flutter pub get }
  if ($Verify) {
    Step 'flutter analyze' { flutter analyze }
    Step 'flutter test' { & $flutterEnv test }
  }
  Step 'flutter build windows --release' { & $flutterEnv build windows --release }

  if ($Zip) {
    $dist = Join-Path $root 'dist'
    $zipPath = Join-Path $dist 'my-jira-work-time-windows.zip'
    Write-Host "==> Creando $zipPath" -ForegroundColor Cyan
    if (-not $dryRun) {
      New-Item -ItemType Directory -Force $dist | Out-Null
      if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
      Compress-Archive -Path (Join-Path $release '*') -DestinationPath $zipPath
    }
  }

  Write-Host ''
  Write-Host 'Listo.' -ForegroundColor Green
  Write-Host "  App:      $release\gestion_time_proyect.exe"
  Write-Host '  Entrega:  la carpeta Release completa (el .exe solo no funciona).'
  if ($Zip) { Write-Host "  Zip:      $(Join-Path $root 'dist\my-jira-work-time-windows.zip')" }
} finally {
  Pop-Location
}
