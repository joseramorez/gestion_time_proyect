import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/data/repository/projects_repository_impl.dart';
import 'package:gestion_time_proyect/data/datasources/app_database.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppDatabase db;
  late ProjectsController c;

  setUp(() async {
    db = await AppDatabase.open(path: inMemoryDatabasePath);
    c = ProjectsController(ProjectsRepositoryImpl(db));
    await c.load();
  });

  tearDown(() async {
    c.dispose();
    await db.close();
  });

  test('agrega proyectos con nombre, descripción y enlace', () async {
    await c.add('Ticket 1', 'desc', 'https://x.test');
    expect(c.projects.single.name, 'Ticket 1');
    expect(c.projects.single.link, 'https://x.test');
    expect((await db.projects()).length, 1);
  });

  test('el tiempo es independiente por proyecto y solo corre uno a la vez',
      () async {
    await c.add('A', '', '');
    await c.add('B', '', '');
    await c.start(c.projects[0]);
    expect(c.projects[0].isRunning, isTrue);

    await c.start(c.projects[1]);
    expect(c.projects[0].isRunning, isFalse);
    expect(c.projects[1].isRunning, isTrue);
  });

  test('pausar conserva el tiempo y reanudar continúa', () async {
    await c.add('A', '', '');
    await c.start(c.projects.first);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await c.pause(c.projects.first);
    final paused = c.projects.first.accumulatedMs;
    expect(paused, greaterThan(0));
    expect((await db.projects()).first.accumulatedMs, paused);

    await c.start(c.projects.first);
    expect(c.projects.first.accumulatedMs, paused);
    expect(c.projects.first.isRunning, isTrue);
  });

  test('limpiar deja en cero y detiene', () async {
    await c.add('A', '', '');
    await c.start(c.projects.first);
    await c.clear(c.projects.first);
    expect(c.projects.first.elapsed(), Duration.zero);
    expect(c.projects.first.isRunning, isFalse);
  });

  test('persiste la transparencia y la limita al mínimo', () async {
    await c.setOpacity(0.6);
    await c.setOpacity(0.0, persist: false);
    expect(c.opacity, ProjectsController.minOpacity);
    await c.setOpacity(0.6);
    final c2 = ProjectsController(ProjectsRepositoryImpl(db));
    await c2.load();
    expect(c2.opacity, 0.6);
    c2.dispose();
  });

  test('persiste la preferencia de superposición', () async {
    await c.setAlwaysOnTop(true);
    final c2 = ProjectsController(ProjectsRepositoryImpl(db));
    await c2.load();
    expect(c2.alwaysOnTop, isTrue);
    c2.dispose();
  });
}
