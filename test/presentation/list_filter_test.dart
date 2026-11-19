import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/data/datasources/jira_api.dart';
import 'package:gestion_time_proyect/data/datasources/jira_oauth.dart';
import 'package:gestion_time_proyect/data/datasources/secret_store.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/domain/entities/project_filter.dart';
import 'package:gestion_time_proyect/presentation/screens/home_page.dart';
import 'package:gestion_time_proyect/presentation/viewModels/daily_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';

import '../support/fakes.dart';

void main() {
  late FakeProjectsRepository repo;
  late ProjectsController projects;
  late DailyController daily;
  late JiraController jira;
  late FakeWindowService window;

  Future<void> setUpData() async {
    repo = FakeProjectsRepository();
    await repo.insert(const Project(
      name: 'ABC-1 Pagos',
      jiraKey: 'ABC-1',
      jiraStatus: 'Por hacer',
      jiraStatusCategory: 'new',
      accumulatedMs: 40 * 60000,
    ));
    await repo.insert(const Project(
      name: 'ABC-2 Login',
      jiraKey: 'ABC-2',
      jiraStatus: 'En curso',
      jiraStatusCategory: 'indeterminate',
      accumulatedMs: 10 * 60000,
    ));
    await repo.insert(const Project(
      name: 'ABC-3 Reportes',
      jiraKey: 'ABC-3',
      jiraStatus: 'Listo',
      jiraStatusCategory: 'done',
      accumulatedMs: 20 * 60000,
    ));
    await repo.insert(const Project(name: 'Reunión', accumulatedMs: 30 * 60000));
    projects = ProjectsController(repo);
    await projects.load();
    window = FakeWindowService();
    jira = JiraController(
      store: MemorySecretStore(),
      oauth: JiraOAuth(openBrowser: (_) async => false),
      api: JiraApi(),
    );
    daily = DailyController(projects, FakeWorkLogRepository(), goal: const Duration(hours: 8));
    await daily.load();
  }

  void uiTest(String name, Future<void> Function(WidgetTester tester) body) {
    testWidgets(name, (tester) async {
      await setUpData();
      tester.view.physicalSize = const Size(700, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // `showFittedDialog` consulta el tamaño de la ventana nativa: aquí no existe.
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async => call.method == 'getBounds'
            ? {'x': 0.0, 'y': 0.0, 'width': 700.0, 'height': 3000.0}
            : null,
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('window_manager'), null));
      await tester.pumpWidget(MaterialApp(
        home: HomePage(controller: projects, jira: jira, daily: daily, window: window),
      ));
      await tester.pumpAndSettle();
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        daily.dispose();
        projects.dispose();
      }
    });
  }

  uiTest('escribir en la búsqueda filtra la lista y avisa cuántos se ven', (tester) async {
    expect(find.text('ABC-1 Pagos'), findsOneWidget);
    expect(find.text('Reunión'), findsOneWidget);
    expect(find.textContaining('Mostrando'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'reunion');
    await tester.pumpAndSettle();

    expect(find.text('Reunión'), findsOneWidget);
    expect(find.text('ABC-1 Pagos'), findsNothing);
    expect(find.text('Mostrando 1 de 4'), findsOneWidget);
    // lo oculto no desaparece de los totales: el filtro solo cambia lo que se dibuja
    expect(projects.projects, hasLength(4));
    expect(projects.hiddenCount, 3);
  });

  uiTest('«Limpiar» devuelve toda la lista y vacía el cuadro de búsqueda', (tester) async {
    await tester.enterText(find.byType(TextField).first, 'login');
    await tester.pumpAndSettle();
    expect(find.text('ABC-2 Login'), findsOneWidget);
    expect(find.text('ABC-1 Pagos'), findsNothing);

    await tester.tap(find.text('Limpiar'));
    await tester.pumpAndSettle();

    expect(find.text('ABC-1 Pagos'), findsOneWidget);
    expect(find.textContaining('Mostrando'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, '');
  });

  uiTest('el diálogo filtra por estado y por origen', (tester) async {
    await tester.tap(find.byTooltip('Filtros'));
    await tester.pumpAndSettle();
    expect(find.text('Filtros'), findsWidgets);

    await tester.tap(find.widgetWithText(FilterChip, 'Listo'));
    await tester.pumpAndSettle();
    expect(projects.filter.statuses, {'Listo'});

    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('ABC-3 Reportes'), findsOneWidget);
    expect(find.text('ABC-1 Pagos'), findsNothing);
    expect(find.text('Mostrando 1 de 4'), findsOneWidget);

    await projects.setFilter(const ProjectFilter(origin: ProjectOrigin.manual));
    await tester.pumpAndSettle();
    expect(find.text('Reunión'), findsOneWidget);
    expect(find.text('ABC-3 Reportes'), findsNothing);
  });

  uiTest('ordenar por nombre desde el menú reordena la lista', (tester) async {
    await tester.tap(find.byType(PopupMenuButton<ProjectSort>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nombre (A–Z)'));
    await tester.pumpAndSettle();

    expect(projects.filter.sort, ProjectSort.name);
    final names = projects.visibleProjects.map((p) => p.name).toList();
    expect(names, ['ABC-1 Pagos', 'ABC-2 Login', 'ABC-3 Reportes', 'Reunión']);
    expect(repo.settings['list_filter'], contains('"sort":"name"'));
  });

  uiTest('si nada coincide hay un estado vacío propio con «Limpiar filtros»', (tester) async {
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('Ningún ticket coincide'), findsOneWidget);
    expect(find.text('Aún no hay proyectos'), findsNothing);

    await tester.tap(find.text('Limpiar filtros'));
    await tester.pumpAndSettle();
    expect(find.text('ABC-1 Pagos'), findsOneWidget);
  });

  testWidgets('con finalizados ocultos avisa y «Mostrar finalizados» los trae', (tester) async {
    await setUpData();
    // un finalizado sin nada pendiente: se esconde por defecto
    await repo.insert(const Project(
      name: 'ABC-9 Cerrado',
      jiraKey: 'ABC-9',
      jiraStatus: 'Listo',
      jiraStatusCategory: 'done',
    ));
    await projects.load();
    tester.view.physicalSize = const Size(700, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: HomePage(controller: projects, jira: jira, daily: daily, window: window),
    ));
    await tester.pumpAndSettle();

    expect(find.text('ABC-9 Cerrado'), findsNothing);
    expect(find.text('Mostrando 4 de 5'), findsOneWidget);
    expect(projects.filter.isActive, isFalse); // no es un filtro: es lo normal

    await tester.tap(find.text('Mostrar finalizados'));
    await tester.pumpAndSettle();
    expect(find.text('ABC-9 Cerrado'), findsOneWidget);
    expect(projects.filter.hideDone, isFalse);

    // ahora sí hay un filtro activo y «Limpiar» vuelve a ocultarlos
    await tester.tap(find.text('Limpiar'));
    await tester.pumpAndSettle();
    expect(find.text('ABC-9 Cerrado'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    daily.dispose();
    projects.dispose();
  });

  test('los filtros se guardan, se restauran y la búsqueda no', () async {
    await setUpData();
    await projects.setFilter(const ProjectFilter(
      query: 'abc',
      hideDone: true,
      sort: ProjectSort.mostTime,
    ));
    expect(repo.settingWrites['list_filter'], 1);

    // cambiar solo la búsqueda no vuelve a escribir
    await projects.setFilter(projects.filter.copyWith(query: 'abcd'));
    expect(repo.settingWrites['list_filter'], 1);

    final again = ProjectsController(repo);
    await again.load();
    expect(again.filter.hideDone, isTrue);
    expect(again.filter.sort, ProjectSort.mostTime);
    expect(again.filter.query, '');
    again.dispose();
    daily.dispose();
    projects.dispose();
  });
}
