import 'package:gestion_time_proyect/domain/entities/project.dart';

/// Sitio de Jira Cloud al que la cuenta da acceso a la app.
class JiraSite {
  const JiraSite({required this.id, required this.name, required this.url});

  final String id;
  final String name;
  final String url;
}

class TokenSet {
  const TokenSet({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.scope,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;

  /// Scopes concedidos, separados por espacios, tal como los devuelve Atlassian.
  /// `null` en sesiones guardadas antes de que existiera el corte a Jira.
  final String? scope;

  bool get isExpired => !DateTime.now().isBefore(expiresAt);
}

/// Sesión iniciada: tokens + sitios Jira a los que da acceso la cuenta.
class JiraSession {
  const JiraSession({
    required this.tokens,
    required this.sites,
    required this.siteId,
  });

  final TokenSet tokens;
  final List<JiraSite> sites;
  final String siteId;

  /// ¿La sesión permite escribir en Jira (registrar tiempo)? Las sesiones
  /// antiguas solo tenían lectura y no guardaron el scope: piden iniciar de nuevo.
  bool get canWrite =>
      (tokens.scope ?? '').split(' ').contains('write:jira-work');

  JiraSite get site =>
      sites.firstWhere((s) => s.id == siteId, orElse: () => sites.first);

  JiraSession copyWith({TokenSet? tokens, String? siteId}) => JiraSession(
    tokens: tokens ?? this.tokens,
    sites: sites,
    siteId: siteId ?? this.siteId,
  );
}

/// Un ticket tal como lo devuelve Jira.
class JiraIssue {
  const JiraIssue({
    required this.key,
    required this.summary,
    required this.description,
    required this.url,
    this.parentKey,
    this.status,
    this.statusCategory,
    this.estimateSeconds,
    this.remainingSeconds,
    this.spentSeconds,
  });

  final String key;
  final String summary;
  final String description;
  final String url;

  /// Clave del issue padre si esto es una subtarea.
  final String? parentKey;

  /// Estado actual en Jira y su categoría (`new`, `indeterminate`, `done`).
  final String? status;
  final String? statusCategory;

  /// "Seguimiento de tiempo" de Jira (segundos): estimación original, restante y
  /// registrado por todos los usuarios. `null` si Jira no lo informa.
  final int? estimateSeconds;
  final int? remainingSeconds;
  final int? spentSeconds;

  bool get isSubtask => parentKey != null;

  /// El ticket como entrada de la lista de la app.
  Project toProject() => Project(
    name: '$key $summary',
    description: [
      if (isSubtask) 'Subtarea de $parentKey',
      if (description.isNotEmpty) description,
    ].join('\n\n'),
    link: url,
    jiraKey: key,
    jiraStatus: status,
    jiraStatusCategory: statusCategory,
    jiraEstimateSeconds: estimateSeconds,
    jiraRemainingSeconds: remainingSeconds,
    jiraSpentSeconds: spentSeconds,
  );
}

/// Un cambio de estado que Jira permite ahora a un ticket (una *transición* del flujo
/// del proyecto). `id` es lo que se envía para ejecutarla; `toStatus` / `toCategory` son
/// el estado al que lleva y su categoría (`new`, `indeterminate`, `done`).
class JiraTransition {
  const JiraTransition({
    required this.id,
    required this.name,
    required this.toStatus,
    this.toCategory,
  });

  final String id;
  final String name;
  final String toStatus;
  final String? toCategory;
}
