import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/data/datasources/jira_api.dart';
import 'package:gestion_time_proyect/data/datasources/jira_oauth.dart';
import 'package:gestion_time_proyect/data/datasources/secret_store.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/presentation/screens/day_progress_bar.dart';
import 'package:gestion_time_proyect/presentation/screens/home_page.dart';
import 'package:gestion_time_proyect/presentation/viewModels/daily_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';

import '../support/fakes.dart';

/// La barra del día y el corte del día: lo abre el usuario, lista los tickets con tiempo
/// y sube uno por uno o todos, con horas y minutos.
void main() {
  late FakeProjectsRepository repo;
  late FakeWorkLogRepository log;
  late ProjectsController projects;
  late DailyController daily;
  late JiraController jira;
  late FakeWindowService window;
  final now = DateTime(2026, 11, 12, 10);
  final posted = <({String key, int seconds})>[];

  /// Como `testWidgets`, liberando los controladores dentro del cuerpo (el
  /// cronómetro y el reloj del día dejan temporizadores periódicos).
  void uiTest(String name, Future<void> Function(WidgetTester tester) body,
      {bool signedIn = true, bool carried = false}) {
    testWidgets(name, (tester) async {
      posted.clear();
      repo = FakeProjectsRepository();
      log = FakeWorkLogRepository();
      window = FakeWindowService();
      // A: 1 h 23 m 40 s · B: 40 m · C manual 30 m · D: 30 s (no llega a 1 minuto)
      await repo.insert(Project(
        name: 'ABC-1 Pagos',
        jiraKey: 'ABC-1',
        accumulatedMs: 5020000,
        timeSinceMs:
            carried ? DateTime(2026, 11, 11, 9).millisecondsSinceEpoch : null,
      ));
      await repo.insert(
          const Project(name: 'ABC-2 Login', jiraKey: 'ABC-2', accumulatedMs: 2400000));
      await repo.insert(const Project(name: 'Tarea manual', accumulatedMs: 1800000));
      await repo.insert(
          const Project(name: 'ABC-4 Corto', jiraKey: 'ABC-4', accumulatedMs: 30000));
      projects = ProjectsController(
        repo,
        work: log,
        clock: () => now,
        canStart: (p) => !daily.isStartBlocked(p),
      );
      jira = JiraController(
        store: MemorySecretStore(),
        oauth: JiraOAuth(openBrowser: (_) async => false),
        api: JiraApi(),
      );
      daily = DailyController(
        projects,
        log,
        goal: const Duration(hours: 8),
        clock: () => now,
        canPost: () => signedIn,
        post: ({required issueKey, required seconds, required started, comment = ''}) async {
          posted.add((key: issueKey, seconds: seconds));
          return null;
        },
      );
      await projects.load();
      await daily.load();

      tester.view.physicalSize = const Size(500, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      try {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark(),
          home: HomePage(controller: projects, jira: jira, daily: daily, window: window),
        ));
        await tester.pumpAndSettle();
        await body(tester);
      } finally {
        daily.dispose();
        projects.dispose();
      }
    });
  }

  Future<void> openCut(WidgetTester tester) async {
    await tester.tap(find.byTooltip(DayProgressBar.cutTooltip));
    await tester.pumpAndSettle();
  }

  const title = 'Corte del día';

  uiTest('la barra suma los tickets de ahora y el corte no se abre solo', (tester) async {
    expect(find.textContaining('Hoy 2 h 34 m / 8 h'), findsOneWidget);
    expect(find.textContaining('subido'), findsNothing);
    expect(find.text(title), findsNothing);
  });

  uiTest('nada bloquea: el play funciona', (tester) async {
    await tester.tap(find.byTooltip('Reanudar').first);
    await tester.pump();
    expect(projects.projects.first.isRunning, isTrue);
  });

  uiTest('el botón abre el corte y lista los tickets con tiempo', (tester) async {
    await openCut(tester);
    expect(find.text(title), findsOneWidget);
    expect(find.text('ABC-1 Pagos'), findsWidgets);
    expect(find.text('ABC-2 Login'), findsWidgets);
    expect(find.text('Tarea manual'), findsWidgets);
    // el de menos de 1 minuto no aparece
    expect(find.text('ABC-4 Corto'), findsOneWidget); // solo en la lista de fondo
    // horas y minutos sin segundos; el manual no se sube
    expect(find.widgetWithText(TextField, 's'), findsNothing);
    expect(find.widgetWithText(TextField, 'h'), findsNWidgets(2));
    expect(find.widgetWithText(TextField, 'min'), findsNWidgets(2));
    expect(find.textContaining('manual: no se sube'), findsOneWidget);
    expect(find.text('Reportado 2 h 3 m / 8 h'), findsOneWidget);
    expect(find.text('Faltan 5 h 57 m (mínimo 7 h)'), findsOneWidget);
  });

  uiTest('los campos traen lo medido sin segundos', (tester) async {
    await openCut(tester);
    final hours = tester.widgetList<TextField>(find.widgetWithText(TextField, 'h'));
    final mins = tester.widgetList<TextField>(find.widgetWithText(TextField, 'min'));
    expect(hours.map((f) => f.controller!.text), ['1', '0']);
    expect(mins.map((f) => f.controller!.text), ['23', '40']);
  });

  uiTest('se cierra con Esc y con Cerrar', (tester) async {
    await openCut(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text(title), findsNothing);

    await openCut(tester);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text(title), findsNothing);
  });

  uiTest('sin sesión de Jira avisa y no deja subir', (tester) async {
    await openCut(tester);
    expect(find.text('No has iniciado sesión en Jira, así que no se puede subir.'),
        findsOneWidget);
    expect(find.text('Abrir Jira'), findsOneWidget);
    final all = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Subir todos (2)'));
    expect(all.onPressed, isNull);
  }, signedIn: false);

  uiTest('editar horas y minutos cambia el total y el aviso', (tester) async {
    await openCut(tester);
    await tester.enterText(find.widgetWithText(TextField, 'h').first, '5');
    await tester.enterText(find.widgetWithText(TextField, 'min').first, '20');
    await tester.pump();
    // 5 h 20 m + 40 m = 6 h
    expect(find.text('Reportado 6 h / 8 h'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'min').last, '100');
    await tester.pump();
    expect(find.textContaining('Reportado'), findsOneWidget);
  });

  uiTest('el aviso pasa por faltan, aceptable, día completo y sobran', (tester) async {
    await openCut(tester);
    Future<void> setFirst(String h, String m) async {
      await tester.enterText(find.widgetWithText(TextField, 'h').first, h);
      await tester.enterText(find.widgetWithText(TextField, 'min').first, m);
      await tester.pump();
    }

    await setFirst('6', '20'); // + 40 m = 7 h
    expect(find.text('Aceptable · faltan 1 h'), findsOneWidget);
    await setFirst('7', '20'); // 8 h
    expect(find.text('Día completo'), findsOneWidget);
    await setFirst('8', '20'); // 9 h
    expect(find.text('Sobran 1 h'), findsOneWidget);
    // nada se bloquea por pasarse
    final all = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Subir todos (2)'));
    expect(all.onPressed, isNotNull);
  });

  uiTest('subir un ticket por separado', (tester) async {
    await openCut(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Subir').first);
    await tester.pumpAndSettle();

    expect(posted.map((p) => (p.key, p.seconds)), [('ABC-1', 83 * 60)]);
    expect(find.text('✓ Subido 1 h 23 m'), findsOneWidget);
    // el otro sigue pendiente
    expect(find.widgetWithText(TextButton, 'Subir'), findsOneWidget);
    expect(projects.projects.first.elapsed(now), Duration.zero);
    // en la barra, lo subido va aparte
    expect(find.textContaining('subido 1 h 23 m'), findsOneWidget);
  });

  uiTest('subir todos de una vez', (tester) async {
    await openCut(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Subir todos (2)'));
    await tester.pumpAndSettle();

    expect(posted.map((p) => (p.key, p.seconds)), [('ABC-1', 4980), ('ABC-2', 2400)]);
    expect(find.text('✓ Subido 1 h 23 m'), findsOneWidget);
    expect(find.text('✓ Subido 40 m'), findsOneWidget);
    expect(find.text('Reportado 2 h 3 m / 8 h'), findsOneWidget);
    // lo manual no se toca
    expect(projects.projects[2].elapsed(now), const Duration(minutes: 30));
  });

  uiTest('sin reiniciar el cronómetro conserva lo que sobra', (tester) async {
    await openCut(tester);
    await tester.tap(find.text('Reiniciar el cronómetro al subir'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Subir').first);
    await tester.pumpAndSettle();
    expect(projects.projects.first.elapsed(now), const Duration(seconds: 40));
  });

  uiTest('en la ventana mínima el corte no se desborda (hay scroll)', (tester) async {
    tester.view.physicalSize = const Size(360, 242);
    await tester.pumpAndSettle();
    await openCut(tester);
    expect(tester.takeException(), isNull);
    expect(find.text(title), findsOneWidget);
  });

  uiTest('con tiempo de ayer: avisa en la barra y en el corte, y sugiere ayer', (tester) async {
    expect(find.textContaining('Un ticket con tiempo de días anteriores'), findsOneWidget);
    await openCut(tester);
    expect(find.textContaining('Un ticket trae tiempo de un día anterior'), findsOneWidget);
    expect(find.textContaining('trae tiempo de ayer'), findsOneWidget);
    // el día sugerido para ese ticket es ayer; el otro, hoy
    expect(find.text('Ayer (11/11)'), findsOneWidget);
    expect(find.text('Hoy'), findsOneWidget);
  }, carried: true);

  uiTest('sin tiempo de otros días no hay aviso', (tester) async {
    expect(find.textContaining('días anteriores'), findsNothing);
    await openCut(tester);
    expect(find.textContaining('trae tiempo'), findsNothing);
    expect(find.textContaining('Ayer'), findsNothing);
  });

  uiTest('subir un ticket de ayer lo anota en ayer y no en lo subido hoy', (tester) async {
    await openCut(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Subir').first);
    await tester.pumpAndSettle();

    expect(log.sent['2026-11-11'], {1: 83 * 60});
    expect(log.sent['2026-11-12'], isNull);
    expect(daily.sentToday, Duration.zero);
    expect(find.text('✓ Subido 1 h 23 m · Ayer (11/11)'), findsOneWidget);
    // ya no trae tiempo de otro día: el aviso de la barra desaparece
    expect(find.textContaining('días anteriores'), findsNothing);
  }, carried: true);

  uiTest('se puede cambiar el día trabajado', (tester) async {
    await openCut(tester);
    await tester.tap(find.text('Ayer (11/11)'));
    await tester.pumpAndSettle();
    // solo hay dos escenarios: hoy y el registro anterior
    expect(find.textContaining('Anterior'), findsNothing);
    expect(find.text('Hoy'), findsWidgets);
    await tester.tap(find.text('Hoy').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Subir').first);
    await tester.pumpAndSettle();

    expect(log.sent['2026-11-12'], {1: 83 * 60});
    expect(daily.sentToday, const Duration(minutes: 83));
  }, carried: true);

  uiTest('el total frente a la meta solo cuenta lo de hoy', (tester) async {
    await openCut(tester);
    // ABC-1 va a ayer (83 min) y ABC-2 a hoy (40 min)
    expect(find.text('Reportado 40 m / 8 h'), findsOneWidget);
    expect(find.textContaining('para otros días 1 h 23 m'), findsOneWidget);
  }, carried: true);

  uiTest('un ticket con tiempo de otro día no se puede iniciar y explica por qué', (tester) async {
    const why = 'Sube o limpia primero el tiempo del 11/11 de este ticket';
    expect(find.byTooltip(why), findsOneWidget);
    // el resto de tickets se inicia con normalidad
    expect(find.byTooltip('Reanudar'), findsWidgets);
    await tester.tap(find.byTooltip(why));
    await tester.pump();
    expect(projects.projects.first.isRunning, isFalse);
  }, carried: true);

  uiTest('sin tiempo de otros días el play no se bloquea', (tester) async {
    expect(find.textContaining('Sube o limpia primero'), findsNothing);
    expect(find.byTooltip('Reanudar'), findsWidgets);
  });

  uiTest('el corte de la tarjeta de ese ticket abre el corte del día', (tester) async {
    await tester.tap(find.byTooltip('Cortar y enviar a Jira').first);
    await tester.pumpAndSettle();
    expect(find.text(title), findsOneWidget);
    expect(find.text('Cortar y enviar a Jira'), findsNothing);
  }, carried: true);

  uiTest('al subirlo desde el corte, el play se desbloquea', (tester) async {
    await openCut(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Subir').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sube o limpia primero'), findsNothing);
    await tester.tap(find.byTooltip('Iniciar').first);
    await tester.pump();
    expect(projects.projects.first.isRunning, isTrue);
  }, carried: true);
}
