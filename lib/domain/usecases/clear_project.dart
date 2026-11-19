import 'package:gestion_time_proyect/domain/entities/project.dart';

/// Limpiar: deja el tiempo en cero y detiene el cronómetro. No toca nada de lo
/// ya enviado a Jira.
class ClearProject {
  const ClearProject();

  Project call(Project project) =>
      project.copyWith(
        accumulatedMs: 0,
        startedAtMs: () => null,
        timeSinceMs: () => null,
      );
}
