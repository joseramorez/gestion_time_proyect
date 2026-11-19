import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/presentation/screens/close_guard.dart';
import 'package:gestion_time_proyect/presentation/viewModels/daily_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';

import '../support/fakes.dart';

void main() {
  late FakeProjectsRepository repo;
  late FakeWorkLogRepository log;
  late ProjectsController projects;
  late DailyController daily;
  late FakeWindowService window;
  var now = DateTime(2026, 11, 12, 10);
  var canPost = true;
  var failPost = false;
  final posted = <({String key, int seconds})>[];

  Future<String?> post({
    required String issueKey,
    required int seconds,
    required DateTime started,
    String comment = '',
  }) async {
    if (failPost) return 'Jira rechazó $issueKey';
    posted.add((key: issueKey, seconds: seconds));
    return null;
  }

  Future<void> setUpWith(List<Project> rows) async {
    now = DateTime(2026, 11, 12, 10);
    canPost = true;
    failPost = false;
    posted.clear();
    repo = FakeProjectsRepository();
    log = FakeWorkLogRepository();
    window = FakeWindowService();
    for (final r in rows) {
      await repo.insert(r);
    }
    projects = ProjectsController(repo, work: log, clock: () => now);
    await projects.load();
    daily = DailyController(
      projects,
      log,
      goal: const Duration(hours: 8),
      clock: () => now,
      post: post,
      canPost: () => canPost,
    );
    await daily.load();
  }

  Future<void> pumpGuard(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CloseGuard(
          controller: projects,
          daily: daily,
          window: window,
          child: const Scaffold(body: Text('home')),
        ),
      ),
    );
  }

  /// Los `testWidgets` con un cronómetro en marcha dejan el ticker del controlador:
  /// se desecha dentro del cuerpo de la prueba.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    daily.dispose();
    projects.dispose();
  }

  group('opción "Confirmar al cerrar"', () {
    test('por defecto está activa y se guarda al cambiarla', () async {
      await setUpWith([const Project(name: 'A')]);
      expect(projects.confirmClose, isTrue);
      await projects.setConfirmClose(false);
      expect(repo.settings['confirm_close'], '0');

      final again = ProjectsController(repo);
      await again.load();
      expect(again.confirmClose, isFalse);
      again.dispose();
      projects.dispose();
      daily.dispose();
    });
  });

  group('pausar y subir al cerrar (controlador)', () {
    test('pausa el ticket en curso y sube su tiempo a Jira con reinicio', () async {
      await setUpWith([const Project(name: 'A', jiraKey: 'ABC-1')]);
      await projects.start(projects.projects.first);
      now = now.add(const Duration(minutes: 42, seconds: 30));

      final errors = await daily.pauseAndUploadRunning();

      expect(errors, isEmpty);
      expect(posted, [(key: 'ABC-1', seconds: 42 * 60)]);
      expect(projects.running, isEmpty);
      expect(projects.projects.first.elapsed(now), Duration.zero);
      expect(daily.sentToday, const Duration(minutes: 42));
      projects.dispose();
      daily.dispose();
    });

    test('un ticket manual o con menos de 1 min solo se pausa', () async {
      await setUpWith([const Project(name: 'Manual')]);
      await projects.start(projects.projects.first);
      now = now.add(const Duration(minutes: 5));
      expect(daily.uploadableRunning, isEmpty);

      final errors = await daily.pauseAndUploadRunning();

      expect(errors, isEmpty);
      expect(posted, isEmpty);
      expect(projects.running, isEmpty);
      expect(projects.projects.first.elapsed(now), const Duration(minutes: 5));
      projects.dispose();
      daily.dispose();
    });

    test('si Jira rechaza, queda pausado con su tiempo intacto y se informa', () async {
      await setUpWith([const Project(name: 'A', jiraKey: 'ABC-1')]);
      await projects.start(projects.projects.first);
      now = now.add(const Duration(minutes: 30));
      failPost = true;

      final errors = await daily.pauseAndUploadRunning();

      expect(errors.values.single, contains('rechazó'));
      expect(projects.running, isEmpty);
      expect(projects.projects.first.elapsed(now), const Duration(minutes: 30));
      projects.dispose();
      daily.dispose();
    });
  });

  group('guardia de cierre (ventana)', () {
    testWidgets('retiene la X y, sin tiempos corriendo, pide confirmar', (tester) async {
      await setUpWith([const Project(name: 'A')]);
      await pumpGuard(tester);
      expect(window.preventClose, isTrue);

      window.requestClose();
      await tester.pumpAndSettle();
      expect(find.text('¿Cerrar la aplicación?'), findsOneWidget);
      expect(find.text('No hay tiempos corriendo.'), findsOneWidget);
      expect(window.closed, isFalse);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(window.closed, isFalse);

      window.requestClose();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(window.closed, isTrue);
      await dispose(tester);
    });

    testWidgets('con la opción apagada y nada corriendo cierra sin preguntar', (tester) async {
      await setUpWith([const Project(name: 'A')]);
      await projects.setConfirmClose(false);
      await pumpGuard(tester);

      window.requestClose();
      await tester.pumpAndSettle();
      expect(find.text('¿Cerrar la aplicación?'), findsNothing);
      expect(window.closed, isTrue);
      await dispose(tester);
    });

    testWidgets('con un ticket en curso ofrece pausar, subir o dejarlo corriendo', (tester) async {
      await setUpWith([const Project(name: 'A', jiraKey: 'ABC-1')]);
      await projects.start(projects.projects.first);
      now = now.add(const Duration(minutes: 10));
      await pumpGuard(tester);

      window.requestClose();
      await tester.pumpAndSettle();
      expect(find.text('Tienes un ticket en curso:'), findsOneWidget);
      expect(find.text('Pausar y cerrar'), findsOneWidget);
      expect(find.text('Subir a Jira y cerrar'), findsOneWidget);
      expect(find.text('Dejar corriendo'), findsOneWidget);

      // Dejar corriendo: cierra y el cronómetro sigue en marcha.
      await tester.tap(find.text('Dejar corriendo'));
      await tester.pumpAndSettle();
      expect(window.closed, isTrue);
      expect(projects.running, hasLength(1));
      await dispose(tester);
    });

    testWidgets('"Pausar y cerrar" pausa el ticket y cierra', (tester) async {
      await setUpWith([const Project(name: 'A', jiraKey: 'ABC-1')]);
      await projects.start(projects.projects.first);
      now = now.add(const Duration(minutes: 10));
      await pumpGuard(tester);

      window.requestClose();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pausar y cerrar'));
      await tester.pumpAndSettle();

      expect(projects.running, isEmpty);
      expect(posted, isEmpty);
      expect(window.closed, isTrue);
      await dispose(tester);
    });

    testWidgets('"Subir a Jira y cerrar" sube y cierra', (tester) async {
      await setUpWith([const Project(name: 'A', jiraKey: 'ABC-1')]);
      await projects.start(projects.projects.first);
      now = now.add(const Duration(minutes: 10));
      await pumpGuard(tester);

      window.requestClose();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Subir a Jira y cerrar'));
      await tester.pumpAndSettle();

      expect(posted, [(key: 'ABC-1', seconds: 600)]);
      expect(window.closed, isTrue);
      await dispose(tester);
    });

    testWidgets('si Jira falla NO cierra y muestra el error', (tester) async {
      await setUpWith([const Project(name: 'A', jiraKey: 'ABC-1')]);
      await projects.start(projects.projects.first);
      now = now.add(const Duration(minutes: 10));
      failPost = true;
      await pumpGuard(tester);

      window.requestClose();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Subir a Jira y cerrar'));
      await tester.pumpAndSettle();

      expect(window.closed, isFalse);
      expect(find.textContaining('rechazó'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('sin sesión de Jira el botón de subir está desactivado', (tester) async {
      await setUpWith([const Project(name: 'A', jiraKey: 'ABC-1')]);
      canPost = false;
      await projects.start(projects.projects.first);
      now = now.add(const Duration(minutes: 10));
      await pumpGuard(tester);

      window.requestClose();
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Subir a Jira y cerrar'),
      );
      expect(button.onPressed, isNull);
      await dispose(tester);
    });
  });
}
