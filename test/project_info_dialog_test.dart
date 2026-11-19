import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/data/repository/projects_repository_impl.dart';
import 'package:gestion_time_proyect/data/datasources/app_database.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:gestion_time_proyect/presentation/screens/dialogs/project_info_dialog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppDatabase db;
  late ProjectsController controller;

  setUp(() async {
    // sqflite necesita el reloj real, no el simulado de testWidgets.
    db = await AppDatabase.open(path: inMemoryDatabasePath);
    controller = ProjectsController(ProjectsRepositoryImpl(db));
    await controller.load();
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  /// Abre el diálogo de información de un ticket en una ventana de `size`.
  Future<void> openInfo(
    WidgetTester tester, {
    required Size size,
    required String description,
    String link = '',
    String? jiraKey,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      if (jiraKey == null) {
        await controller.add('Ticket de prueba', description, link);
      } else {
        await controller.importJira([
          Project(
              name: '$jiraKey Ticket de prueba',
              description: description,
              link: link,
              jiraKey: jiraKey),
        ]);
      }
    });

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                showProjectInfo(context, controller, controller.projects.first),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  double dialogHeight(WidgetTester tester) =>
      tester.getSize(find.byType(Dialog)).height;

  final long = List.generate(60, (i) => 'palabra$i').join(' ');

  testWidgets('una descripción enorme no pasa del alto de la ventana', (tester) async {
    await openInfo(tester,
        size: const Size(300, 220), description: long, link: 'https://x.test/ruta/larga');

    expect(tester.takeException(), isNull); // sin overflow
    expect(dialogHeight(tester), lessThanOrEqualTo(220));
    expect(find.text('Ver más'), findsOneWidget);
    // Se dibuja truncada con puntos suspensivos (el widget conserva el texto
    // completo, por eso se comprueba el recorte y no el contenido).
    final text = tester.widget<Text>(find.text(long));
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.maxLines, isNotNull);
  });

  testWidgets('"Ver más" abre la descripción en una zona acotada y "Ver menos" la cierra',
      (tester) async {
    await openInfo(tester, size: const Size(300, 220), description: long);

    // En la ventana mínima el botón puede quedar bajo el borde visible del
    // diálogo: hay que desplazarse hasta él, como haría el usuario.
    await tester.ensureVisible(find.text('Ver más'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver más'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Dialog), findsOneWidget); // no se abrió otro diálogo
    expect(dialogHeight(tester), lessThanOrEqualTo(220));
    expect(find.text('Ver menos'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);

    await tester.ensureVisible(find.text('Ver menos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver menos'));
    await tester.pumpAndSettle();
    expect(find.text('Ver más'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en una ventana alta una descripción corta se ve completa, sin "Ver más"',
      (tester) async {
    await openInfo(tester,
        size: const Size(800, 900),
        description: 'Revisar el flujo de pagos y avisar a QA.',
        link: 'https://x.test',
        jiraKey: 'ABC-1');

    expect(find.text('Revisar el flujo de pagos y avisar a QA.'), findsOneWidget);
    expect(find.text('Ver más'), findsNothing);
    expect(find.text('Jira · ABC-1'), findsOneWidget);
    expect(find.text('https://x.test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin descripción muestra un texto de reemplazo', (tester) async {
    await openInfo(tester, size: const Size(300, 220), description: '');

    expect(find.text('Sin descripción'), findsOneWidget);
    expect(find.text('Ver más'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
