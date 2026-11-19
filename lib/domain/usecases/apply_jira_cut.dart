import 'package:gestion_time_proyect/domain/entities/project.dart';

/// Corte hacia Jira: `sentMs` ya quedó registrado como worklog. Se descuenta del
/// cronómetro y se suma al total enviado (`jiraLoggedMs`).
///
///  * Si se envió **menos** de lo medido, lo que sobra se conserva.
///  * Si se envió **más**, el cronómetro queda en cero.
///  * Con `reset`, el cronómetro **se reinicia**: queda en cero aunque sobrara tiempo
///    (p. ej. los segundos que no se suben).
///  * Si corría, **sigue corriendo** con lo que quede; si estaba pausado, queda
///    pausado. Así no se pierde el tiempo que pasó mientras estaba abierto el
///    diálogo o durante la llamada de red.
class ApplyJiraCut {
  const ApplyJiraCut();

  Project call(
    Project project,
    int sentMs,
    DateTime now, {
    bool reset = false,
  }) {
    final remaining = reset
        ? 0
        : (project.elapsed(now).inMilliseconds - sentMs).clamp(0, 1 << 62);
    return project.copyWith(
      accumulatedMs: project.isRunning ? 0 : remaining,
      startedAtMs: project.isRunning
          ? () => now.millisecondsSinceEpoch - remaining
          : () => null,
      // Sin nada que quede, el tiempo vuelve a empezar (ahora, si sigue corriendo).
      timeSinceMs: () => remaining == 0
          ? (project.isRunning ? now.millisecondsSinceEpoch : null)
          : project.timeSinceMs,
      jiraLoggedMs: project.jiraLoggedMs + sentMs,
    );
  }
}
