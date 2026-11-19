/// Datos de un ticket que Jira puede cambiar sin que la app lo sepa: su estado
/// y el "Seguimiento de tiempo". Se usa para refrescar entradas ya importadas.
///
/// Los tiempos están en segundos y son `null` cuando Jira no los informa (el
/// seguimiento de tiempo puede estar desactivado en el proyecto, o el ticket no
/// tener estimación). `null` y `0` no son lo mismo: sin estimación no hay
/// "estimado 0".
class JiraLive {
  const JiraLive({
    this.status,
    this.category,
    this.estimateSeconds,
    this.remainingSeconds,
    this.spentSeconds,
  });

  /// Nombre del estado y su categoría (`new`, `indeterminate`, `done`).
  final String? status;
  final String? category;

  /// Estimación original, tiempo restante estimado y tiempo ya registrado en
  /// Jira (suma de los worklogs de todos los usuarios).
  final int? estimateSeconds;
  final int? remainingSeconds;
  final int? spentSeconds;
}
