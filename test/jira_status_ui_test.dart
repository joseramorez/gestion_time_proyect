// Las pruebas de widget van en su propio archivo: con una prueba de widget en el
// archivo, Flutter intercepta las conexiones HTTP reales (también las de
// localhost), y eso rompe las pruebas que arrancan el servidor local de OAuth.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/data/repository/projects_repository_impl.dart';
import 'package:gestion_time_proyect/data/datasources/app_database.dart';
import 'package:gestion_time_proyect/data/datasources/jira_api.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';
import 'package:gestion_time_proyect/domain/entities/jira_entities.dart';
import 'package:gestion_time_proyect/data/datasources/jira_oauth.dart';
import 'package:gestion_time_proyect/data/datasources/secret_store.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:gestion_time_proyect/presentation/screens/home_page.dart';
import 'package:gestion_time_proyect/presentation/screens/dialogs/project_info_dialog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('estado de Jira en la interfaz', () {
    late AppDatabase db;
    late ProjectsController projects;
    late JiraController jira;

    setUp(() async {
      db = await AppDatabase.open(path: inMemoryDatabasePath);
      projects = ProjectsController(ProjectsRepositoryImpl(db));
      await projects.load();
      jira = JiraController(
        store: MemorySecretStore(),
        oauth: JiraOAuth(openBrowser: (_) async => false),
        api: JiraApi(),
      );
    });

    tearDown(() async {
      projects.dispose();
      await db.close();
    });

    Future<void> seed(WidgetTester tester) async {
      // 360 es el ancho mínimo de la ventana de la app (antes 300).
      tester.view.physicalSize = const Size(360, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await projects.importJira([
          const JiraIssue(
                  key: 'ABC-1', summary: 'Pagos', description: 'x', url: 'https://x.test',
                  status: 'En curso', statusCategory: 'indeterminate')
              .toProject(),
          const JiraIssue(key: 'ABC-2', summary: 'Sin estado', description: '', url: 'u')
              .toProject(),
        ]);
        await projects.add('Manual', '', '');
      });
    }

    testWidgets('la tarjeta muestra el estado solo en tickets de Jira que lo tienen',
        (tester) async {
      await seed(tester);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(children: [
            for (final p in projects.projects)
              ProjectTile(project: p, controller: projects, jira: jira),
          ]),
        ),
      ));

      expect(find.text('En curso'), findsOneWidget);
      expect(find.text('Por hacer'), findsNothing);
      // ABC-2 es de Jira pero aún no trae estado: se avisa, no se deja un hueco mudo.
      expect(find.text('Sin sincronizar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la etiqueta queda en el centro de la tarjeta: entre el cronómetro y los botones',
        (tester) async {
      await seed(tester);
      tester.view.physicalSize = const Size(360, 400);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProjectTile(
              project: projects.projects.first, controller: projects, jira: jira),
        ),
      ));

      final chip = tester.getRect(find.text('En curso'));
      final time = tester.getRect(find.text('00:00:00'));
      final restart = tester.getRect(find.byTooltip('Limpiar tiempo'));

      expect(chip.left, greaterThan(time.right)); // a la derecha del cronómetro
      expect(chip.right, lessThan(restart.left)); // y antes de los botones
      // Está en el hueco central, no pegada a ningún extremo.
      final gapLeft = chip.left - time.right;
      final gapRight = restart.left - chip.right;
      expect((gapLeft - gapRight).abs(), lessThan(40));
      expect(tester.takeException(), isNull);
    });

    testWidgets('un estado largo no desborda la tarjeta al ancho mínimo nuevo (360)',
        (tester) async {
      tester.view.physicalSize = const Size(360, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => projects.importJira([
            const JiraIssue(
                    key: 'ABC-9',
                    summary: 'Despliegue a producción',
                    description: '',
                    url: 'u',
                    status: 'Esperando revisión de QA y aprobación',
                    statusCategory: 'indeterminate')
                .toProject(),
          ]));
      await tester.runAsync(() => db.update(
          projects.projects.single.copyWith(jiraLoggedMs: 3900000)));
      await tester.runAsync(() => projects.load());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ProjectTile(
              project: projects.projects.single, controller: projects, jira: jira),
        ),
      ));

      expect(find.textContaining('Esperando'), findsOneWidget);
      expect(find.textContaining('En Jira:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    Future<void> openInfoFor(WidgetTester tester, String key) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showProjectInfo(context, projects,
                  projects.projects.firstWhere((p) => p.jiraKey == key)),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('el detalle muestra el seguimiento de tiempo de Jira', (tester) async {
      tester.view.physicalSize = const Size(700, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => projects.importJira([
            const JiraIssue(
                    key: 'ABC-5', summary: 'Pagos', description: '', url: 'u',
                    status: 'En curso', statusCategory: 'indeterminate',
                    estimateSeconds: 10800, remainingSeconds: 3600, spentSeconds: 7200)
                .toProject(),
          ]));
      await openInfoFor(tester, 'ABC-5');

      expect(find.text('SEGUIMIENTO DE TIEMPO · JIRA'), findsOneWidget);
      expect(find.text('3 h 00 m'), findsOneWidget); // estimado
      expect(find.text('2 h 00 m'), findsOneWidget); // registrado
      expect(find.text('1 h 00 m'), findsOneWidget); // restante
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Se pasó de la estimación.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('avisa si lo registrado supera la estimación y muestra "—" lo que falta',
        (tester) async {
      tester.view.physicalSize = const Size(700, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => projects.importJira([
            const JiraIssue(
                    key: 'ABC-6', summary: 'Pasado', description: '', url: 'u',
                    estimateSeconds: 3600, spentSeconds: 5400)
                .toProject(),
          ]));
      await openInfoFor(tester, 'ABC-6');

      expect(find.text('Se pasó de la estimación.'), findsOneWidget);
      expect(find.text('—'), findsOneWidget); // restante: Jira no lo informa
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin seguimiento de tiempo no se muestra la sección y no se desborda en la ventana mínima',
        (tester) async {
      await seed(tester);
      tester.view.physicalSize = const Size(300, 220);
      await openInfoFor(tester, 'ABC-1');

      expect(find.text('SEGUIMIENTO DE TIEMPO · JIRA'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con seguimiento de tiempo tampoco se desborda en la ventana mínima',
        (tester) async {
      tester.view.physicalSize = const Size(300, 220);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => projects.importJira([
            JiraIssue(
                    key: 'ABC-7', summary: 'Largo', description: List.filled(40, 'texto').join(' '),
                    url: 'https://x.test', status: 'En curso',
                    estimateSeconds: 7200, remainingSeconds: 3600, spentSeconds: 3600)
                .toProject(),
          ]));
      await openInfoFor(tester, 'ABC-7');

      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.getSize(find.byType(Dialog)).height, lessThanOrEqualTo(220));
      expect(tester.takeException(), isNull);
    });

    testWidgets('el detalle del ticket muestra el estado', (tester) async {
      await seed(tester);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showProjectInfo(context, projects, projects.projects.first),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('En curso'), findsOneWidget);
      expect(find.text('Jira · ABC-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
