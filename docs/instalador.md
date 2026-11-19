# Compilar e instalar en Windows

Resumen de lo hecho para tener la app instalable: opción "Iniciar con el equipo", build de
release, copia al escritorio e instalador MSI. Todos los comandos se ejecutan desde la raíz
del proyecto en PowerShell.

## 1. Opción "Iniciar con el equipo"

Interruptor en el diálogo **Ventana** (botón de transparencia/superposición del AppBar).

- Paquete: `launch_at_startup` (Windows: registro; macOS: LaunchAgent; Linux: `.desktop` de autostart).
- `lib/core/services/startup_service.dart`: interfaz `StartupService` + `OsStartupService`.
- `HomePage` recibe `startup` como parámetro **opcional**; si es `null` (tests) el interruptor no se muestra.
- La fuente de verdad es el sistema operativo, no SQLite: se lee `isEnabled()` al abrir el diálogo.
- Registra la ruta del ejecutable en uso: actívalo desde la versión instalada, no desde `flutter run`.

## 2. Compilar la versión de release

```powershell
.\build_windows.ps1              # solo compila
.\build_windows.ps1 -Verify -Zip # analyze + test antes, y deja dist\my-jira-work-time-windows.zip
```

Resultado: `build\windows\x64\runner\Release\`. Hay que distribuir **toda** la carpeta, no solo el `.exe`.
Las credenciales de Jira de `.env` se compilan dentro del `.exe` (no lo repartas fuera del equipo).
Cierra la app antes de compilar: un `.exe` abierto bloquea el reemplazo.

## 3. Copia manual al escritorio

```powershell
$src = 'D:\LABORATORIO\gestion_time_proyect\build\windows\x64\runner\Release'
$dst = "$([Environment]::GetFolderPath('Desktop'))\my-jira-work-time"
robocopy $src $dst /E /NFL /NDL /NJH /NJS

$exe = "$dst\gestion_time_proyect.exe"
$s = (New-Object -ComObject WScript.Shell).CreateShortcut("$([Environment]::GetFolderPath('Desktop'))\my-jira-work-time.lnk")
$s.TargetPath = $exe; $s.WorkingDirectory = $dst; $s.IconLocation = "$exe,0"; $s.Save()
```

Para actualizar: cierra la app, recompila y vuelve a copiar encima.

## 4. Instalador MSI

### Requisito (una sola vez)

```powershell
dotnet tool install --global wix --version 5.0.2
wix --version
```

### Generar

```powershell
.\build_msi.ps1          # usa el Release existente (o lo compila si falta)
.\build_msi.ps1 -Build   # recompila Windows antes
```

Salida: `dist\my-jira-work-time-<version>.msi` (+ `.wixpdb`, solo depuración, se puede borrar).
La versión sale de `pubspec.yaml` sin el `+build` (`1.0.0+1` → `1.0.0`): súbela antes de
cada entrega.

### Qué hace el MSI (`tool/installer/Package.wxs`)

- Instalación **por usuario**, sin administrador: `%LOCALAPPDATA%\my-jira-work-time`.
- Accesos directos en el menú Inicio y en el escritorio (`my-jira-work-time.lnk`).
- `MajorUpgrade`: una versión mayor reemplaza a la anterior; una menor se rechaza.
- `UpgradeCode` fijo (`6B1D2C0E-4F7A-4C55-9B1E-3A2D7C8E5F10`): **no lo cambies** o las
  actualizaciones dejarán de reconocer la instalación anterior.
- Los archivos se recogen con `<Files Include="...\**">`; el `.exe` va aparte en su componente.
- No firmado: SmartScreen puede avisar de "editor desconocido".

### Probar instalación y desinstalación

```powershell
$msi = 'D:\LABORATORIO\gestion_time_proyect\dist\my-jira-work-time-1.0.0.msi'

# instalar en silencio con log
msiexec /i $msi /qn /l*v "$env:TEMP\tiempo_install.log"
# comprobar
Test-Path "$env:LOCALAPPDATA\my-jira-work-time\gestion_time_proyect.exe"

# desinstalar
msiexec /x $msi /qn /l*v "$env:TEMP\tiempo_uninstall.log"
Test-Path "$env:LOCALAPPDATA\my-jira-work-time"   # debe dar False
```

Resultado de la prueba: instalar y desinstalar terminan con código 0; la desinstalación
borra carpeta, accesos y clave `HKCU\Software\my-jira-work-time`, y **conserva** la base de datos en
`%APPDATA%\com.jarm\gestion_time_proyect\gestion_time.db`.

## Notas

- El `my-jira-work-time.lnk` manual del escritorio (apartado 3) y el del MSI tienen el mismo nombre: el
  MSI lo sobrescribe y al desinstalar lo borra. Si instalas el MSI, elimina la carpeta
  `Desktop\my-jira-work-time` para no tener dos copias.
- Si mueves o borras la carpeta desde la que se activó "Iniciar con el equipo", el arranque
  deja de funcionar: desactívalo y vuelve a activarlo desde la copia definitiva.
- Los cambios no están en un commit: `build_msi.ps1`, `tool/installer/` y este documento son
  archivos nuevos sin añadir.
