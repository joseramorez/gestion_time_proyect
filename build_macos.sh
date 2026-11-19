#!/usr/bin/env bash
# Compila la app para macOS en modo release. Hay que ejecutarlo EN un Mac.
#
# Ejecuta `flutter pub get` y `tool/flutter_env.sh build macos --release` (que añade las
# credenciales de Jira de `.env` solo si ese archivo existe). Al terminar muestra dónde
# quedó el .app.
#
#   ./build_macos.sh             compila
#   ./build_macos.sh --verify    antes corre `flutter analyze` y `flutter test` (se detiene si fallan)
#   ./build_macos.sh --zip       al final deja dist/my-jira-work-time-macos.zip listo para entregar
#   ./build_macos.sh --dmg       al final deja dist/my-jira-work-time-<version>.dmg (con acceso a /Applications)
#   DRY_RUN=1 ./build_macos.sh   muestra los pasos sin ejecutarlos
#
# La primera vez: `chmod +x build_macos.sh tool/flutter_env.sh` (o ejecútalo con `bash`).
# El .app queda SIN firmar ni notarizar: en otro Mac, Gatekeeper pedirá aprobarlo.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
verify=0
zip=0
dmg=0
for arg in "$@"; do
  case "$arg" in
    --verify) verify=1 ;;
    --zip) zip=1 ;;
    --dmg) dmg=1 ;;
    -h | --help)
      sed -n '2,13p' "$0"
      exit 0
      ;;
    *)
      echo "Opción desconocida: $arg (usa --verify, --zip, --dmg o --help)" >&2
      exit 2
      ;;
  esac
done

dry="${DRY_RUN:-0}"
app="$root/build/macos/Build/Products/Release/gestion_time_proyect.app"

step() {
  echo "==> $1"
  shift
  if [ "$dry" = "1" ]; then
    echo "    (DRY_RUN) $*"
  else
    "$@"
  fi
}

if [ "$dry" != "1" ] && [ "$(uname -s)" != "Darwin" ]; then
  echo "Este script solo compila en macOS (estás en $(uname -s))." >&2
  exit 1
fi

cd "$root"
step "flutter pub get" flutter pub get
if [ "$verify" = "1" ]; then
  step "flutter analyze" flutter analyze
  step "flutter test" "$root/tool/flutter_env.sh" test
fi
step "flutter build macos --release" "$root/tool/flutter_env.sh" build macos --release

zip_path="$root/dist/my-jira-work-time-macos.zip"
if [ "$zip" = "1" ]; then
  echo "==> Creando $zip_path"
  if [ "$dry" != "1" ]; then
    mkdir -p "$root/dist"
    rm -f "$zip_path"
    # ditto conserva los atributos del .app (zip normal puede dejarlo inservible).
    ditto -c -k --keepParent "$app" "$zip_path"
  fi
fi

version="$(sed -n 's/^version:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' "$root/pubspec.yaml" | head -n1)"
dmg_path="$root/dist/my-jira-work-time-$version.dmg"
if [ "$dmg" = "1" ]; then
  echo "==> Creando $dmg_path"
  if [ "$dry" != "1" ]; then
    mkdir -p "$root/dist"
    rm -f "$dmg_path"
    stage="$(mktemp -d)"
    trap 'rm -rf "$stage"' EXIT
    ditto "$app" "$stage/my-jira-work-time.app"
    ln -s /Applications "$stage/Applications"
    hdiutil create -volname "my-jira-work-time" -srcfolder "$stage" -ov -format UDZO "$dmg_path"
  fi
fi

echo
echo "Listo."
echo "  App:  $app"
if [ "$zip" = "1" ]; then echo "  Zip:  $zip_path"; fi
if [ "$dmg" = "1" ]; then echo "  Dmg:  $dmg_path"; fi
