import 'package:gestion_time_proyect/data/datasources/app_database.dart';
import 'package:gestion_time_proyect/domain/repositories/work_log_repository.dart';

/// Implementación de `WorkLogRepository` sobre SQLite (`AppDatabase`).
class WorkLogRepositoryImpl implements WorkLogRepository {
  WorkLogRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<Map<int, int>> sentOn(String day) => _db.daySentOn(day);

  @override
  Future<void> addSent(String day, int projectId, int seconds) =>
      _db.addDaySent(day, projectId, seconds);

  @override
  Future<void> deleteForProject(int projectId) =>
      _db.deleteDaySentOf(projectId);
}
