<#
.SYNOPSIS
  Ejecuta `flutter` pasando las credenciales de Jira desde `.env` SOLO si ese archivo existe.

.DESCRIPTION
  `flutter run --dart-define-from-file=.env` falla si el archivo no existe, asi que no se
  puede poner siempre. Este script lo anade unicamente cuando hay `.env`; sin el, la app se
  compila sin credenciales y las pide al usuario (y las guarda en el almacen seguro).

  Solo toca los comandos que compilan la app: run, build y test.

  No declara parametros con nombre a proposito: cualquier nombre (-DryRun, -Debug...)
  chocaria con las abreviaturas de las opciones de flutter (-d, -t, -v...).

.EXAMPLE
  powershell -File tool\flutter_env.ps1 run -d windows
  powershell -File tool\flutter_env.ps1 build windows --release

  Para ver el comando sin ejecutarlo:  $env:DRY_RUN = '1'
#>
$flutterArgs = @($args)
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root '.env'
$compiling = $flutterArgs.Count -gt 0 -and $flutterArgs[0] -in @('run', 'build', 'test')

if ($compiling -and (Test-Path $envFile)) {
  # Aviso si el .env esta incompleto: con una sola clave la app lo trata como "sin credenciales".
  $text = Get-Content $envFile -Raw
  $hasId = $text -match '(?m)^\s*JIRA_CLIENT_ID\s*=\s*\S'
  $hasSecret = $text -match '(?m)^\s*JIRA_CLIENT_SECRET\s*=\s*\S'
  if ($hasId -and $hasSecret) {
    Write-Host 'Usando las credenciales de Jira de .env (se compilan en la app).'
  } else {
    Write-Warning '.env existe pero le falta JIRA_CLIENT_ID o JIRA_CLIENT_SECRET: la app pedira las credenciales.'
  }
  $flutterArgs += "--dart-define-from-file=$envFile"
} elseif ($compiling) {
  Write-Host 'No hay .env: la app pedira las credenciales de Jira (ver .env.example).'
}

if ($env:DRY_RUN -eq '1') {
  Write-Output ('flutter ' + ($flutterArgs -join ' '))
  exit 0
}

Push-Location $root
try { & flutter @flutterArgs; exit $LASTEXITCODE } finally { Pop-Location }
