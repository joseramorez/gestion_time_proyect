#!/usr/bin/env bash
# Ejecuta `flutter` pasando las credenciales de Jira desde `.env` SOLO si ese archivo existe.
#
# `flutter run --dart-define-from-file=.env` falla si el archivo no existe, así que no se
# puede poner siempre. Este script lo añade únicamente cuando hay `.env`; sin él, la app se
# compila sin credenciales y las pide al usuario (y las guarda en el almacén seguro).
# Solo toca los comandos que compilan la app: run, build y test.
#
#   tool/flutter_env.sh run -d macos
#   tool/flutter_env.sh build linux --release
#   DRY_RUN=1 tool/flutter_env.sh run -d macos      # muestra el comando, no lo ejecuta
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
env_file="$root/.env"
args=("$@")

case "${1:-}" in
  run | build | test)
    if [ -f "$env_file" ]; then
      if grep -Eq '^[[:space:]]*JIRA_CLIENT_ID[[:space:]]*=[[:space:]]*[^[:space:]]' "$env_file" &&
        grep -Eq '^[[:space:]]*JIRA_CLIENT_SECRET[[:space:]]*=[[:space:]]*[^[:space:]]' "$env_file"; then
        echo "Usando las credenciales de Jira de .env (se compilan en la app)."
      else
        echo "AVISO: .env existe pero le falta JIRA_CLIENT_ID o JIRA_CLIENT_SECRET: la app pedirá las credenciales." >&2
      fi
      args+=("--dart-define-from-file=$env_file")
    else
      echo "No hay .env: la app pedirá las credenciales de Jira (ver .env.example)."
    fi
    ;;
esac

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "flutter ${args[*]}"
  exit 0
fi

cd "$root"
exec flutter "${args[@]}"
