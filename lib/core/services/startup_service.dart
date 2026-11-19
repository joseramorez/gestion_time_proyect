import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';

/// Arranque automático de la app al iniciar sesión en el equipo.
///
/// La fuente de verdad es el propio sistema operativo (registro en Windows,
/// LaunchAgent en macOS, `.desktop` de autostart en Linux), no la base de datos:
/// así, si el usuario lo quita desde el sistema, la app lo refleja bien.
abstract interface class StartupService {
  Future<bool> isEnabled();
  Future<void> setEnabled(bool value);
}

/// Implementación real con `launch_at_startup`.
class OsStartupService implements StartupService {
  OsStartupService({String appName = 'Tiempo'}) {
    LaunchAtStartup.instance.setup(
      appName: appName,
      appPath: Platform.resolvedExecutable,
    );
  }

  @override
  Future<bool> isEnabled() => LaunchAtStartup.instance.isEnabled();

  @override
  Future<void> setEnabled(bool value) => value
      ? LaunchAtStartup.instance.enable()
      : LaunchAtStartup.instance.disable();
}
