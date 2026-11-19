import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gestion_time_proyect/domain/entities/jira_live.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/data/models/project_model.dart';

/// Acceso a SQLite. Los cambios se escriben en cuanto ocurren.
class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static Future<AppDatabase> open({String? path}) async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final dbPath =
        path ??
        p.join(
          (await getApplicationSupportDirectory()).path,
          'gestion_time.db',
        );
    if (path == null) {
      await Directory(p.dirname(dbPath)).create(recursive: true);
    }
    final db = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 8,
        // Sin esto SQLite ignora las claves foráneas y `ON DELETE CASCADE` no actúa.
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE projects (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              description TEXT NOT NULL DEFAULT '',
              link TEXT NOT NULL DEFAULT '',
              accumulated_ms INTEGER NOT NULL DEFAULT 0,
              started_at_ms INTEGER,
              time_since_ms INTEGER,
              jira_key TEXT,
              jira_logged_ms INTEGER NOT NULL DEFAULT 0,
              jira_status TEXT,
              jira_status_category TEXT,
              jira_estimate_s INTEGER,
              jira_remaining_s INTEGER,
              jira_spent_s INTEGER
            )
          ''');
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await _createJiraIndex(db);
          await _createDaySent(db);
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE projects ADD COLUMN jira_key TEXT');
            await _createJiraIndex(db);
          }
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE projects ADD COLUMN jira_logged_ms INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (oldVersion < 4) {
            await db.execute(
              'ALTER TABLE projects ADD COLUMN jira_status TEXT',
            );
            await db.execute(
              'ALTER TABLE projects ADD COLUMN jira_status_category TEXT',
            );
          }
          if (oldVersion < 5) {
            await db.execute(
              'ALTER TABLE projects ADD COLUMN jira_estimate_s INTEGER',
            );
            await db.execute(
              'ALTER TABLE projects ADD COLUMN jira_remaining_s INTEGER',
            );
            await db.execute(
              'ALTER TABLE projects ADD COLUMN jira_spent_s INTEGER',
            );
          }
          if (oldVersion < 6) {
            await _createDaySent(db);
          }
          if (oldVersion < 7) {
            // El historial de tramos y los cortes diarios obligatorios se retiraron: el
            // progreso del día sale ahora de los cronómetros actuales.
            await db.execute('DROP TABLE IF EXISTS work_intervals');
            await db.execute('DROP TABLE IF EXISTS day_cuts');
          }
          if (oldVersion < 8) {
            // Desde cuándo viene el tiempo de cada ticket; lo anterior no se puede saber.
            await db.execute(
              'ALTER TABLE projects ADD COLUMN time_since_ms INTEGER',
            );
          }
        },
      ),
    );
    return AppDatabase._(db);
  }

  /// Lo subido a Jira cada día por ticket (para "subido hoy"). Cae con el ticket.
  static Future<void> _createDaySent(Database db) => db.execute('''
    CREATE TABLE IF NOT EXISTS day_sent (
      day TEXT NOT NULL,
      project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
      seconds INTEGER NOT NULL,
      PRIMARY KEY (day, project_id)
    )
  ''');

  static Future<void> _createJiraIndex(Database db) => db.execute(
    'CREATE UNIQUE INDEX idx_projects_jira_key ON projects(jira_key) '
    'WHERE jira_key IS NOT NULL',
  );

  /// Inserta o actualiza una entrada importada de Jira, identificada por su
  /// clave. Al actualizar solo cambia nombre, descripción, enlace y los datos de
  /// Jira (estado y seguimiento de tiempo): el tiempo medido aquí y el estado del
  /// cronómetro no se tocan. Devuelve `true` si es nueva.
  Future<bool> upsertJira(Project issue) async {
    final key = issue.jiraKey!;
    final updated = await _db.update(
      'projects',
      {
        'name': issue.name,
        'description': issue.description,
        'link': issue.link,
        'jira_status': issue.jiraStatus,
        'jira_status_category': issue.jiraStatusCategory,
        'jira_estimate_s': issue.jiraEstimateSeconds,
        'jira_remaining_s': issue.jiraRemainingSeconds,
        'jira_spent_s': issue.jiraSpentSeconds,
      },
      where: 'jira_key = ?',
      whereArgs: [key],
    );
    if (updated > 0) return false;
    await _db.insert('projects', ProjectModel.toMap(issue));
    return true;
  }

  /// Actualiza solo los datos de Jira (estado y seguimiento de tiempo) de varias
  /// entradas, por clave. Un valor `null` sí se escribe: significa que Jira ya no
  /// lo informa (p. ej. le quitaron la estimación).
  Future<void> setJiraLive(Map<String, JiraLive> byKey) async {
    final batch = _db.batch();
    byKey.forEach(
      (key, v) => batch.update(
        'projects',
        {
          'jira_status': v.status,
          'jira_status_category': v.category,
          'jira_estimate_s': v.estimateSeconds,
          'jira_remaining_s': v.remainingSeconds,
          'jira_spent_s': v.spentSeconds,
        },
        where: 'jira_key = ?',
        whereArgs: [key],
      ),
    );
    await batch.commit(noResult: true);
  }

  Future<List<Project>> projects() async {
    final rows = await _db.query('projects', orderBy: 'id');
    return rows.map(ProjectModel.fromMap).toList();
  }

  Future<int> insert(Project project) =>
      _db.insert('projects', ProjectModel.toMap(project));

  Future<void> update(Project project) => _db.update(
    'projects',
    ProjectModel.toMap(project),
    where: 'id = ?',
    whereArgs: [project.id],
  );

  Future<void> delete(int id) =>
      _db.delete('projects', where: 'id = ?', whereArgs: [id]);

  // --- lo subido a Jira por día ----------------------------------------------------

  Future<Map<int, int>> daySentOn(String day) async {
    final rows = await _db.query(
      'day_sent',
      where: 'day = ?',
      whereArgs: [day],
    );
    return {for (final r in rows) r['project_id'] as int: r['seconds'] as int};
  }

  Future<void> deleteDaySentOf(int projectId) =>
      _db.delete('day_sent', where: 'project_id = ?', whereArgs: [projectId]);

  Future<void> addDaySent(
    String day,
    int projectId,
    int seconds,
  ) => _db.rawInsert(
    'INSERT INTO day_sent (day, project_id, seconds) VALUES (?, ?, ?) '
    'ON CONFLICT(day, project_id) DO UPDATE SET seconds = seconds + excluded.seconds',
    [day, projectId, seconds],
  );

  Future<String?> setting(String key) async {
    final rows = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) => _db.insert('settings', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> close() => _db.close();
}
