import 'package:gestion_time_proyect/data/datasources/app_database.dart';
import 'package:gestion_time_proyect/domain/entities/jira_live.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/domain/repositories/projects_repository.dart';

/// Implementación de `ProjectsRepository` sobre SQLite (`AppDatabase`).
class ProjectsRepositoryImpl implements ProjectsRepository {
  ProjectsRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<List<Project>> projects() => _db.projects();

  @override
  Future<int> insert(Project project) => _db.insert(project);

  @override
  Future<void> update(Project project) => _db.update(project);

  @override
  Future<void> delete(int id) => _db.delete(id);

  @override
  Future<bool> upsertJira(Project issue) => _db.upsertJira(issue);

  @override
  Future<void> setJiraLive(Map<String, JiraLive> byKey) =>
      _db.setJiraLive(byKey);

  @override
  Future<String?> setting(String key) => _db.setting(key);

  @override
  Future<void> setSetting(String key, String value) =>
      _db.setSetting(key, value);
}
