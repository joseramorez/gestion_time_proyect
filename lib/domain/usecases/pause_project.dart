import 'package:gestion_time_proyect/domain/entities/project.dart';

/// Pausa un proyecto: congela el tiempo transcurrido en el acumulado y detiene el
/// cronómetro. Devuelve `null` si el proyecto no estaba corriendo (nada cambia).
class PauseProject {
  const PauseProject();

  Project? call(Project project, DateTime now) {
    if (!project.isRunning) return null;
    return project.copyWith(
      accumulatedMs: project.elapsed(now).inMilliseconds,
      startedAtMs: () => null,
    );
  }
}
