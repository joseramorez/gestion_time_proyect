/// Contrato del registro de lo ya subido a Jira cada día (para mostrar "subido hoy").
abstract interface class WorkLogRepository {
  /// Lo subido a Jira ese día: ticket → segundos.
  Future<Map<int, int>> sentOn(String day);

  /// Suma `seconds` a lo subido del ticket ese día.
  Future<void> addSent(String day, int projectId, int seconds);

  /// Borra lo subido del ticket: se usa al eliminarlo.
  Future<void> deleteForProject(int projectId);
}
