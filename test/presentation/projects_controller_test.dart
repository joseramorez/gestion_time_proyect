import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/domain/entities/jira_live.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';

import '../support/fakes.dart';

/// El view model sobre un repositorio en memoria: sin SQLite, sin plugins.
void main() {
  late FakeProjectsRepository repo;
  late ProjectsController c;

  setUp(() async {
    repo = FakeProjectsRepository();
    c = ProjectsController(repo);
    await c.load();
  });

  tearDown(() => c.dispose());

  group('proyectos y cronómetro', () {
    test('agregar asigna un id y lo guarda en el repositorio', () async {
      await c.add('Ticket', 'desc', 'https://x.test');
      expect(c.projects.single.id, isNotNull);
      expect(c.projects.single.link, 'https://x.test');
      expect(repo.rows.length, 1);
    });

    test('iniciar uno pausa al otro: solo corre un proyecto a la vez', () async {
      await c.add('A', '', '');
      await c.add('B', '', '');
      await c.start(c.projects[0]);
      await c.start(c.projects[1]);
      expect(c.projects[0].isRunning, isFalse);
      expect(c.projects[1].isRunning, isTrue);
      // y el cambio quedó guardado
      expect(repo.rows[1].isRunning, isTrue);
      expect(repo.rows[0].isRunning, isFalse);
    });

    test('pausar conserva el tiempo y limpiar lo deja en cero', () async {
      await c.add('A', '', '');
      await c.start(c.projects.first);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await c.pause(c.projects.first);
      final paused = c.projects.first.accumulatedMs;
      expect(paused, greaterThan(0));

      await c.clear(c.projects.first);
      expect(c.projects.first.accumulatedMs, 0);
      expect(c.projects.first.isRunning, isFalse);
    });

    test('pausar un proyecto que no corre no cambia nada', () async {
      await c.add('A', '', '');
      await c.pause(c.projects.first);
      expect(c.projects.first.accumulatedMs, 0);
    });

    test('el corte descuenta lo enviado y suma al total (regla de ApplyJiraCut)', () async {
      await c.importJira([const Project(name: 'K-1 x', jiraKey: 'K-1')]);
      repo.rows[0] = repo.rows[0].copyWith(accumulatedMs: 200000);
      await c.load();

      await c.registerJiraCut(c.projects.single, 90000);

      expect(c.projects.single.accumulatedMs, 110000);
      expect(c.projects.single.jiraLoggedMs, 90000);
      expect(repo.rows.single.jiraLoggedMs, 90000);
    });

    test('eliminar quita la entrada de la lista y del repositorio', () async {
      await c.add('A', '', '');
      await c.remove(c.projects.single);
      expect(c.projects, isEmpty);
      expect(repo.rows, isEmpty);
    });
  });

  group('Jira', () {
    test('importar cuenta nuevas y actualizadas sin perder el tiempo medido', () async {
      final first = await c.importJira([
        const Project(name: 'K-1 a', jiraKey: 'K-1', jiraStatus: 'Por hacer'),
      ]);
      expect((first.added, first.updated), (1, 0));
      repo.rows[0] = repo.rows[0].copyWith(accumulatedMs: 5000);

      final second = await c.importJira([
        const Project(name: 'K-1 b', jiraKey: 'K-1', jiraStatus: 'En curso'),
      ]);
      expect((second.added, second.updated), (0, 1));
      expect(c.projects.single.name, 'K-1 b');
      expect(c.projects.single.jiraStatus, 'En curso');
      expect(c.projects.single.accumulatedMs, 5000);
    });

    test('updateJiraLive refresca estado y seguimiento; vacío no hace nada', () async {
      await c.importJira([const Project(name: 'K-1 a', jiraKey: 'K-1')]);
      await c.updateJiraLive({});
      expect(c.projects.single.jiraStatus, isNull);

      await c.updateJiraLive({
        'K-1': const JiraLive(
            status: 'Listo', category: 'done', estimateSeconds: 3600, spentSeconds: 5400),
      });
      expect(c.projects.single.jiraStatus, 'Listo');
      expect(c.projects.single.jiraEstimateSeconds, 3600);
      expect(c.projects.single.jiraRemainingSeconds, isNull); // no informado = null
    });
  });

  group('vista simple', () {
    test('por defecto la app está en la vista completa', () {
      expect(c.compactMode, isFalse);
    });

    /// Un ticket en curso: sin él la vista simple no está permitida.
    Future<void> startOne() async {
      await c.add('A', '', '');
      await c.start(c.projects.single);
    }

    test('sin ticket en curso no se puede entrar en la vista simple', () async {
      expect(c.canUseCompactMode, isFalse);
      var notified = 0;
      c.addListener(() => notified++);

      c.setCompactMode(true);

      expect(c.compactMode, isFalse);
      expect(notified, 0);

      // Con un ticket parado tampoco: tiene que estar corriendo.
      await c.add('Parado', '', '');
      c.setCompactMode(true);
      expect(c.compactMode, isFalse);
    });

    test('con un ticket en curso sí se puede, y pausarlo quita el permiso', () async {
      await startOne();
      expect(c.canUseCompactMode, isTrue);
      c.setCompactMode(true);
      expect(c.compactMode, isTrue);

      await c.pause(c.projects.single);
      expect(c.canUseCompactMode, isFalse);
    });

    test('salir de la vista simple siempre se permite', () async {
      await startOne();
      c.setCompactMode(true);
      await c.pause(c.projects.single); // ya no hay ticket en curso
      c.setCompactMode(false);
      expect(c.compactMode, isFalse);
    });

    test('cambiar de vista notifica una sola vez y es idempotente', () async {
      await startOne();
      var notified = 0;
      c.addListener(() => notified++);
      c.setCompactMode(true);
      c.setCompactMode(true); // sin cambio
      expect(c.compactMode, isTrue);
      expect(notified, 1);
      c.setCompactMode(false);
      expect(notified, 2);
    });

    test('la vista simple NO se guarda: la app siempre arranca en la completa', () async {
      await startOne();
      c.setCompactMode(true);
      final restarted = ProjectsController(repo);
      await restarted.load();
      expect(restarted.compactMode, isFalse);
      expect(repo.settings.keys, isNot(contains('compact')));
      restarted.dispose();
    });

    test('su transparencia es independiente de la de la vista completa', () async {
      await c.setOpacity(0.9);
      await c.setCompactOpacity(0.5);
      expect(c.opacity, 0.9);
      expect(c.compactOpacity, 0.5);
      // cada una en su propia preferencia
      expect(repo.settings['opacity'], '0.9');
      expect(repo.settings['opacity_compact'], '0.5');
    });

    test('la transparencia de la vista simple respeta el mínimo (0.3) y el máximo (1.0)',
        () async {
      await c.setCompactOpacity(0.0);
      expect(c.compactOpacity, ProjectsController.minOpacity);
      await c.setCompactOpacity(5);
      expect(c.compactOpacity, 1.0);
    });

    test('con persist:false (arrastrando el deslizador) no escribe en el repositorio',
        () async {
      await c.setCompactOpacity(0.6, persist: false);
      expect(c.compactOpacity, 0.6);
      expect(repo.settingWrites['opacity_compact'], isNull);
      await c.setCompactOpacity(0.6); // al soltar sí
      expect(repo.settingWrites['opacity_compact'], 1);
    });

    test('al cargar recupera ambas transparencias', () async {
      await c.setOpacity(0.8);
      await c.setCompactOpacity(0.4);
      final other = ProjectsController(repo);
      await other.load();
      expect(other.opacity, 0.8);
      expect(other.compactOpacity, 0.4);
      other.dispose();
    });

    test('un valor guardado fuera de rango se corrige al cargar', () async {
      repo.settings['opacity_compact'] = '0.01';
      final other = ProjectsController(repo);
      await other.load();
      expect(other.compactOpacity, ProjectsController.minOpacity);
      other.dispose();
    });
  });
}
