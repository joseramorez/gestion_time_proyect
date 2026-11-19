import 'package:gestion_time_proyect/domain/entities/project.dart';

/// Conversión entre la entidad `Project` y las filas de SQLite. La entidad no
/// sabe cómo se guarda; eso es cosa de la capa de datos.
abstract final class ProjectModel {
  static Map<String, Object?> toMap(Project p) => {
    if (p.id != null) 'id': p.id,
    'name': p.name,
    'description': p.description,
    'link': p.link,
    'accumulated_ms': p.accumulatedMs,
    'started_at_ms': p.startedAtMs,
    'time_since_ms': p.timeSinceMs,
    'jira_key': p.jiraKey,
    'jira_logged_ms': p.jiraLoggedMs,
    'jira_status': p.jiraStatus,
    'jira_status_category': p.jiraStatusCategory,
    'jira_estimate_s': p.jiraEstimateSeconds,
    'jira_remaining_s': p.jiraRemainingSeconds,
    'jira_spent_s': p.jiraSpentSeconds,
  };

  static Project fromMap(Map<String, Object?> m) => Project(
    id: m['id'] as int,
    name: m['name'] as String,
    description: (m['description'] as String?) ?? '',
    link: (m['link'] as String?) ?? '',
    accumulatedMs: (m['accumulated_ms'] as int?) ?? 0,
    startedAtMs: m['started_at_ms'] as int?,
    timeSinceMs: m['time_since_ms'] as int?,
    jiraKey: m['jira_key'] as String?,
    jiraLoggedMs: (m['jira_logged_ms'] as int?) ?? 0,
    jiraStatus: m['jira_status'] as String?,
    jiraStatusCategory: m['jira_status_category'] as String?,
    jiraEstimateSeconds: m['jira_estimate_s'] as int?,
    jiraRemainingSeconds: m['jira_remaining_s'] as int?,
    jiraSpentSeconds: m['jira_spent_s'] as int?,
  );
}
