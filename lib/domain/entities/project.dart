import 'package:gestion_time_proyect/domain/entities/day_key.dart';

/// Proyecto o ticket cronometrado.
///
/// El tiempo se guarda como milisegundos acumulados más, si está corriendo,
/// el instante en que arrancó. Así el cronómetro sobrevive a cerrar la app.
class Project {
  final int? id;
  final String name;
  final String description;
  final String link;
  final int accumulatedMs;
  final int? startedAtMs;

  /// Instante desde el que viene el tiempo medido (cuando el cronómetro dejó de estar
  /// en cero). Sirve para avisar de que trae tiempo de un día anterior. `null` = no se
  /// sabe (datos anteriores a esta función) o no hay tiempo.
  final int? timeSinceMs;

  /// Clave del issue de Jira (p. ej. `ABC-12`) si la entrada se importó de
  /// Jira; `null` si la creó el usuario a mano.
  final String? jiraKey;

  /// Tiempo total ya registrado en Jira (worklogs enviados con el corte).
  final int jiraLoggedMs;

  /// Estado del ticket en Jira ("Por hacer", "En curso"…) y su categoría
  /// (`new`, `indeterminate`, `done`). `null` en entradas manuales o aún sin sincronizar.
  final String? jiraStatus;
  final String? jiraStatusCategory;

  /// "Seguimiento de tiempo" de Jira, en segundos (ver `JiraLive`): estimación
  /// original, restante y tiempo registrado por todos los usuarios. `null` si Jira
  /// no lo informa.
  final int? jiraEstimateSeconds;
  final int? jiraRemainingSeconds;
  final int? jiraSpentSeconds;

  bool get hasJiraTracking =>
      jiraEstimateSeconds != null ||
      jiraRemainingSeconds != null ||
      jiraSpentSeconds != null;

  const Project({
    this.id,
    required this.name,
    this.description = '',
    this.link = '',
    this.accumulatedMs = 0,
    this.startedAtMs,
    this.timeSinceMs,
    this.jiraKey,
    this.jiraLoggedMs = 0,
    this.jiraStatus,
    this.jiraStatusCategory,
    this.jiraEstimateSeconds,
    this.jiraRemainingSeconds,
    this.jiraSpentSeconds,
  });

  bool get isRunning => startedAtMs != null;

  /// Día local (`YYYY-MM-DD`) desde el que viene el tiempo medido, si se sabe.
  String? get timeSinceDay => timeSinceMs == null
      ? null
      : dayKey(DateTime.fromMillisecondsSinceEpoch(timeSinceMs!));

  /// ¿Trae tiempo de un día anterior a `today`? Solo si hay al menos 1 minuto (menos no
  /// se puede subir a Jira) y se sabe desde cuándo viene.
  bool carriesTimeBefore(String today, [DateTime? now]) {
    final since = timeSinceDay;
    final hasTime = elapsed(now).inSeconds >= 60;
    return hasTime && since != null && since.compareTo(today) < 0;
  }

  Duration elapsed([DateTime? now]) {
    final extra = startedAtMs == null
        ? 0
        : (now ?? DateTime.now()).millisecondsSinceEpoch - startedAtMs!;
    return Duration(milliseconds: accumulatedMs + (extra < 0 ? 0 : extra));
  }

  /// Copia con el id asignado por la base de datos al insertarla.
  Project withId(int id) => Project(
    id: id,
    name: name,
    description: description,
    link: link,
    accumulatedMs: accumulatedMs,
    startedAtMs: startedAtMs,
    timeSinceMs: timeSinceMs,
    jiraKey: jiraKey,
    jiraLoggedMs: jiraLoggedMs,
    jiraStatus: jiraStatus,
    jiraStatusCategory: jiraStatusCategory,
    jiraEstimateSeconds: jiraEstimateSeconds,
    jiraRemainingSeconds: jiraRemainingSeconds,
    jiraSpentSeconds: jiraSpentSeconds,
  );

  Project copyWith({
    String? name,
    String? description,
    String? link,
    int? accumulatedMs,
    int? Function()? startedAtMs,
    int? Function()? timeSinceMs,
    int? jiraLoggedMs,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      link: link ?? this.link,
      accumulatedMs: accumulatedMs ?? this.accumulatedMs,
      startedAtMs: startedAtMs != null ? startedAtMs() : this.startedAtMs,
      timeSinceMs: timeSinceMs != null ? timeSinceMs() : this.timeSinceMs,
      jiraKey: jiraKey,
      jiraLoggedMs: jiraLoggedMs ?? this.jiraLoggedMs,
      jiraStatus: jiraStatus,
      jiraStatusCategory: jiraStatusCategory,
      jiraEstimateSeconds: jiraEstimateSeconds,
      jiraRemainingSeconds: jiraRemainingSeconds,
      jiraSpentSeconds: jiraSpentSeconds,
    );
  }
}
