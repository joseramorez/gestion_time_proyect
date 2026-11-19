import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/domain/usecases/pause_project.dart';

/// Inicia o reanuda un proyecto. **Solo uno corre a la vez**: los demás que
/// estuvieran en marcha se pausan en el mismo instante.
///
/// Devuelve únicamente los proyectos que cambian (los pausados y el iniciado),
/// listos para guardar. Si el proyecto ya corría y no hay otros en marcha, la
/// lista queda vacía.
class StartProject {
  const StartProject([this._pause = const PauseProject()]);

  final PauseProject _pause;

  List<Project> call(List<Project> all, int id, DateTime now) {
    final changed = <Project>[];
    for (final other in all) {
      if (other.id == id) continue;
      final paused = _pause(other, now);
      if (paused != null) changed.add(paused);
    }
    final target = all.firstWhere((p) => p.id == id);
    if (!target.isRunning) {
      changed.add(
        target.copyWith(
          startedAtMs: () => now.millisecondsSinceEpoch,
          // Desde cero, el tiempo empieza ahora; si ya había, se conserva desde cuándo.
          timeSinceMs: () => target.accumulatedMs == 0
              ? now.millisecondsSinceEpoch
              : target.timeSinceMs,
        ),
      );
    }
    return changed;
  }
}
