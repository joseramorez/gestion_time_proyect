import 'dart:async';

/// Repite una sincronización con Jira cada `interval` mientras la app está abierta.
///
/// No sabe nada de Jira: `canSync` decide si toca (ajuste activo, sesión iniciada, nada en
/// curso) y `sync` hace el trabajo. Un fallo no detiene el temporizador: el error queda en
/// el estado de Jira y se reintenta en el siguiente turno.
class JiraAutoSync {
  JiraAutoSync({
    required this.interval,
    required this.canSync,
    required this.sync,
  });

  final Duration interval;
  final bool Function() canSync;
  final Future<void> Function() sync;
  Timer? _timer;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => tick());
  }

  /// Un turno: sincroniza solo si `canSync`.
  Future<void> tick() async {
    if (!canSync()) return;
    try {
      await sync();
    } catch (_) {
      // Se reintenta en el siguiente turno.
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
