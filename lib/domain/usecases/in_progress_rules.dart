import 'package:gestion_time_proyect/domain/entities/jira_entities.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';

/// ¿Conviene ofrecer pasar el ticket a «en curso» al iniciar su cronómetro?
/// Sí si es de Jira y su estado es de los de «aún no empezado»: «Backlog» o
/// «Selected for Development» (también en español).
class ShouldOfferInProgress {
  const ShouldOfferInProgress();

  static const _notStarted = {
    'backlog',
    'selected for development',
    'seleccionado para desarrollo',
    'seleccionado para el desarrollo',
    'seleccionada para desarrollo',
    'seleccionada para el desarrollo',
  };

  bool call(Project project) {
    final status = project.jiraStatus;
    if (project.jiraKey == null || status == null) return false;
    return _notStarted.contains(status.trim().toLowerCase());
  }
}

/// Elige, de los cambios de estado que Jira permite, el que lleva a «en curso».
///
/// Entre los de categoría «en curso» (`indeterminate`) prefiere el llamado «In Progress» /
/// «En curso» / «En progreso»; si solo hay uno, ese. Con varios sin un nombre claro
/// devuelve `null` (hay que dejar elegir al usuario).
class PickInProgressTransition {
  const PickInProgressTransition();

  static const _names = {'in progress', 'en curso', 'en progreso'};

  JiraTransition? call(List<JiraTransition> transitions) {
    final candidates = [
      for (final t in transitions)
        if (t.toCategory == 'indeterminate') t,
    ];
    if (candidates.isEmpty) return null;
    for (final t in candidates) {
      if (_names.contains(t.toStatus.trim().toLowerCase())) return t;
    }
    return candidates.length == 1 ? candidates.single : null;
  }
}
