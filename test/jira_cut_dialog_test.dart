import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/data/repository/projects_repository_impl.dart';
import 'package:gestion_time_proyect/data/datasources/app_database.dart';
import 'package:gestion_time_proyect/data/datasources/jira_api.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';
import 'package:gestion_time_proyect/data/datasources/jira_oauth.dart';
import 'package:gestion_time_proyect/data/datasources/secret_store.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:gestion_time_proyect/presentation/screens/dialogs/jira_cut_dialog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
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

  /// Abre el diálogo de corte de un ticket de Jira con 2 m 05 s medidos (se muestran 2 min).
  Future<void> openCut(WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await projects.importJira(
          [const Project(name: 'ABC-1 Revisar pagos', jiraKey: 'ABC-1')]);
      final p = projects.projects.single;
      await db.update(Project(
          id: p.id, name: p.name, jiraKey: 'ABC-1', accumulatedMs: 125000));
      await projects.load();
    });

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                showJiraCutDialog(context, jira, projects, projects.projects.single),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  String fieldText(WidgetTester tester, String label) => tester
      .widget<TextField>(find.widgetWithText(TextField, label))
      .controller!
      .text;

  Future<void> type(WidgetTester tester, String label, String value) async {
    await tester.enterText(find.widgetWithText(TextField, label), value);
    await tester.pump();
  }

  FilledButton sendButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Enviar a Jira'));

  testWidgets('muestra un resumen con el tiempo medido sin segundos', (tester) async {
    await openCut(tester);

    expect(find.text('RESUMEN'), findsOneWidget);
    expect(find.text('ABC-1 Revisar pagos'), findsOneWidget);
    expect(fieldText(tester, 'h'), '0');
    expect(fieldText(tester, 'min'), '2');
    // Los segundos no se piden ni se tienen en cuenta.
    expect(find.widgetWithText(TextField, 's'), findsNothing);
    expect(find.text('Se registrará'), findsOneWidget);
    expect(find.text('2 m 00 s'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNotNull);
    // Sin cambios no se ofrece "Usar el medido".
    expect(find.textContaining('Usar el medido'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('al modificar el tiempo el resumen se actualiza en vivo', (tester) async {
    await openCut(tester);

    await type(tester, 'min', '10');
    expect(find.text('10 m 00 s'), findsOneWidget); // se registrará
    expect(find.text('En cero (se reinicia)'), findsOneWidget);
    expect(find.textContaining('Usar el medido'), findsOneWidget);

    // Sin reiniciar, lo que no se sube se queda en el reloj.
    await tester.tap(find.text('Reiniciar el cronómetro al subir'));
    await type(tester, 'min', '1');
    expect(find.text('1 m 00 s'), findsOneWidget);
    expect(find.text('00:01:05'), findsOneWidget); // quedan 1 m 05 s en el reloj
    expect(tester.takeException(), isNull);
  });

  testWidgets('menos de 1 minuto o más de 24 h deshabilita el envío y avisa', (tester) async {
    await openCut(tester);

    await type(tester, 'min', '0');
    expect(find.text('Mínimo 1 minuto para registrar.'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNull);

    await type(tester, 'h', '25');
    await type(tester, 'min', '0');
    expect(find.text('Máximo 24 horas por registro.'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Usar el medido" restaura el tiempo original', (tester) async {
    await openCut(tester);

    await type(tester, 'min', '30');
    await tester.tap(find.textContaining('Usar el medido'));
    await tester.pump();

    expect(fieldText(tester, 'min'), '2');
    expect(find.textContaining('Usar el medido'), findsNothing);
    expect(sendButton(tester).onPressed, isNotNull);
  });

  testWidgets('en la ventana mínima no se desborda (hay scroll)', (tester) async {
    await openCut(tester);
    tester.view.physicalSize = const Size(300, 220);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Enviar a Jira'), findsOneWidget);
  });
}
