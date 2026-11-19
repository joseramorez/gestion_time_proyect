import 'package:gestion_time_proyect/domain/entities/project.dart';

/// Claves de Jira de las entradas ya importadas que **no** volvieron en la última
/// búsqueda (`seen`). La búsqueda solo trae pendientes asignados al usuario, así
/// que un ticket que pasó a "Listo" o se reasignó dejaría de venir y se quedaría
/// con el estado y el seguimiento de tiempo viejos: hay que refrescarlos aparte.
class FindStaleJiraKeys {
  const FindStaleJiraKeys();

  List<String> call(Iterable<Project> projects, Set<String> seen) => [
    for (final p in projects)
      if (p.jiraKey != null && !seen.contains(p.jiraKey)) p.jiraKey!,
  ];
}
