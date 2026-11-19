import 'package:gestion_time_proyect/domain/entities/jira_live.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';

/// Contrato de almacenamiento de proyectos y preferencias. La capa de dominio y
/// los view models dependen de esta interfaz, no de SQLite: las pruebas pueden
/// usar un doble en memoria y, si algún día cambia el almacenamiento, solo hay
/// que escribir otra implementación.
abstract interface class ProjectsRepository {
  Future<List<Project>> projects();

  /// Inserta y devuelve el id asignado.
  Future<int> insert(Project project);

  Future<void> update(Project project);

  Future<void> delete(int id);

  /// Inserta o actualiza una entrada importada de Jira, identificada por su
  /// clave. Al actualizar solo cambian nombre, descripción, enlace y los datos de
  /// Jira (estado y seguimiento de tiempo): el tiempo medido aquí y el estado del
  /// cronómetro no se tocan. Devuelve `true` si es nueva.
  Future<bool> upsertJira(Project issue);

  /// Actualiza solo los datos de Jira (estado y seguimiento de tiempo) de varias
  /// entradas, por clave. Un valor `null` sí se escribe: significa que Jira ya no
  /// lo informa.
  Future<void> setJiraLive(Map<String, JiraLive> byKey);

  Future<String?> setting(String key);

  Future<void> setSetting(String key, String value);
}
