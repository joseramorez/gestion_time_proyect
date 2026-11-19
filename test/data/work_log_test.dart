import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/data/datasources/app_database.dart';
import 'package:gestion_time_proyect/data/repository/work_log_repository_impl.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Lo subido a Jira por día (SQLite) y la migración v6 → v7.
void main() {
  sqfliteFfiInit();

  group('subido por día', () {
    late AppDatabase db;
    late WorkLogRepositoryImpl work;
    late int a;
    late int b;

    setUp(() async {
      db = await AppDatabase.open(path: inMemoryDatabasePath);
      a = await db.insert(const Project(name: 'A', jiraKey: 'ABC-1'));
      b = await db.insert(const Project(name: 'B', jiraKey: 'ABC-2'));
      work = WorkLogRepositoryImpl(db);
    });

    tearDown(() => db.close());

    test('addSent suma por ticket y sentOn solo devuelve ese día', () async {
      await work.addSent('2026-11-12', a, 600);
      await work.addSent('2026-11-12', a, 300);
      await work.addSent('2026-11-12', b, 60);
      await work.addSent('2026-11-11', a, 9999);
      expect(await work.sentOn('2026-11-12'), {a: 900, b: 60});
      expect(await work.sentOn('2026-11-11'), {a: 9999});
      expect(await work.sentOn('2026-11-13'), isEmpty);
    });

    test('borrar el ticket borra lo subido (cascada y explícito)', () async {
      await work.addSent('2026-11-12', a, 600);
      await db.delete(a);
      expect(await work.sentOn('2026-11-12'), isEmpty);

      await work.addSent('2026-11-12', b, 60);
      await work.deleteForProject(b);
      expect(await work.sentOn('2026-11-12'), isEmpty);
    });
  });

  test('migración v6 → v8: conserva proyectos, ajustes y lo subido y quita el historial',
      () async {
    final dir = Directory.systemTemp.createTempSync('tiempo_v6_');
    final path = p.join(dir.path, 'v6.db');
    addTearDown(() => dir.deleteSync(recursive: true));

    // Una base como la dejaba la versión 6.
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, _) async {
          await d.execute('''
            CREATE TABLE projects (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              description TEXT NOT NULL DEFAULT '',
              link TEXT NOT NULL DEFAULT '',
              accumulated_ms INTEGER NOT NULL DEFAULT 0,
              started_at_ms INTEGER,
              jira_key TEXT,
              jira_logged_ms INTEGER NOT NULL DEFAULT 0,
              jira_status TEXT,
              jira_status_category TEXT,
              jira_estimate_s INTEGER,
              jira_remaining_s INTEGER,
              jira_spent_s INTEGER
            )''');
          await d.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
          await d.execute('''
            CREATE TABLE work_intervals (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
              start_ms INTEGER NOT NULL, end_ms INTEGER)''');
          await d.execute('''
            CREATE TABLE day_cuts (
              day TEXT PRIMARY KEY, cut_at_ms INTEGER NOT NULL,
              total_ms INTEGER NOT NULL, sent INTEGER NOT NULL)''');
          await d.execute('''
            CREATE TABLE day_sent (
              day TEXT NOT NULL,
              project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
              seconds INTEGER NOT NULL, PRIMARY KEY (day, project_id))''');
          await d.insert('projects', {'name': 'Viejo', 'accumulated_ms': 4000});
          await d.insert('settings', {'key': 'opacity', 'value': '0.8'});
          await d.insert('work_intervals', {'project_id': 1, 'start_ms': 1, 'end_ms': 2});
          await d.insert(
              'day_cuts', {'day': '2026-11-11', 'cut_at_ms': 1, 'total_ms': 1, 'sent': 1});
          await d.insert('day_sent', {'day': '2026-11-12', 'project_id': 1, 'seconds': 120});
        },
      ),
    );
    await old.close();

    final db = await AppDatabase.open(path: path);
    final projects = await db.projects();
    expect(projects.single.name, 'Viejo');
    expect(projects.single.accumulatedMs, 4000);
    expect(await db.setting('opacity'), '0.8');
    expect(await db.daySentOn('2026-11-12'), {1: 120});
    // v8: la columna time_since_ms existe y los datos viejos quedan en "no se sabe".
    expect(projects.single.timeSinceMs, isNull);
    await db.close();

    // Las tablas del historial ya no existen.
    final raw = await databaseFactoryFfi.openDatabase(path);
    final tables = (await raw.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
        .map((r) => r['name'])
        .toSet();
    await raw.close();
    expect(tables, isNot(contains('work_intervals')));
    expect(tables, isNot(contains('day_cuts')));
    expect(tables, contains('day_sent'));

    final raw2 = await databaseFactoryFfi.openDatabase(path);
    final cols = (await raw2.rawQuery('PRAGMA table_info(projects)'))
        .map((r) => r['name'])
        .toSet();
    await raw2.close();
    expect(cols, contains('time_since_ms'));
  });
}
