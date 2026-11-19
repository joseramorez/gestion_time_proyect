// Genera las capturas del manual de uso en docs/manual/img/.
//
//   flutter test tool/screenshots/manual_screenshots_test.dart
//
// Dibuja las pantallas REALES de la app con datos de ejemplo (sin tocar tu base de datos
// ni tu sesión de Jira). Está fuera de `test/` para que no corra con la suite normal.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/data/datasources/jira_api.dart';
import 'package:gestion_time_proyect/data/datasources/jira_oauth.dart';
import 'package:gestion_time_proyect/data/datasources/secret_store.dart';
import 'package:gestion_time_proyect/data/models/jira_session_model.dart';
import 'package:gestion_time_proyect/domain/entities/jira_entities.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/presentation/screens/day_progress_bar.dart';
import 'package:gestion_time_proyect/presentation/screens/home_page.dart';
import 'package:gestion_time_proyect/presentation/viewModels/daily_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';

import '../../test/support/fakes.dart';

const _outDir = 'docs/manual/img';
const _ratio = 2.0;

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/Users/Principal/flutter';
  final fonts = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> bytes(String f) async =>
      ByteData.sublistView(await File('$fonts/$f').readAsBytes());

  final roboto = FontLoader('Roboto')
    ..addFont(bytes('roboto-regular.ttf'))
    ..addFont(bytes('roboto-medium.ttf'))
    ..addFont(bytes('roboto-bold.ttf'));
  await roboto.load();
  // La URL de callback del diálogo de Jira pide 'monospace'; en el test se usa Roboto.
  final mono = FontLoader('monospace')..addFont(bytes('robotocondensed-regular.ttf'));
  await mono.load();
  final icons = FontLoader('MaterialIcons')..addFont(bytes('materialicons-regular.otf'));
  await icons.load();
}

/// El título de los diálogos no declara familia tipográfica (en Windows usa la del
/// sistema); en el test se le da Roboto para que no salga como cuadros.
ThemeData _themeWithRoboto() {
  final base = AppTheme.light();
  return base.copyWith(
    dialogTheme: base.dialogTheme.copyWith(
      titleTextStyle: base.dialogTheme.titleTextStyle?.copyWith(fontFamily: 'Roboto'),
    ),
  );
}

void main() {
  final shotKey = GlobalKey();
  late FakeProjectsRepository repo;
  late FakeWorkLogRepository log;
  late ProjectsController projects;
  late DailyController daily;
  late JiraController jira;
  late FakeWindowService window;

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() async {
      final boundary =
          shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: _ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outDir/$name.png');
      await file.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    });
  }

  Future<void> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * _ratio;
    tester.view.devicePixelRatio = _ratio;
    await tester.pumpWidget(
      RepaintBoundary(
        key: shotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _themeWithRoboto(),
          home: HomePage(
            controller: projects,
            jira: jira,
            daily: daily,
            window: window,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // El logo es un asset: se precarga y se vuelve a dibujar.
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/icon/app_icon.png'),
        tester.element(find.byType(Scaffold).first),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('capturas del manual', (tester) async {
    await tester.runAsync(_loadFonts);
    addTearDown(tester.view.reset);
    // `showFittedDialog` consulta el tamaño de la ventana nativa: aquí no existe.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => call.method == 'getBounds'
          ? {'x': 0.0, 'y': 0.0, 'width': 520.0, 'height': 2000.0}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      ),
    );

    final base = DateTime.now();
    int ms(Duration d) => d.inMilliseconds;

    repo = FakeProjectsRepository();
    log = FakeWorkLogRepository();
    window = FakeWindowService();
    await repo.insert(Project(
      name: 'ABC-101 Revisar módulo de pagos',
      jiraKey: 'ABC-101',
      jiraStatus: 'En curso',
      jiraStatusCategory: 'indeterminate',
      startedAtMs: base.subtract(const Duration(minutes: 47, seconds: 12)).millisecondsSinceEpoch,
      accumulatedMs: ms(const Duration(minutes: 35)),
      timeSinceMs: base.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
    ));
    await repo.insert(Project(
      name: 'ABC-102 Corregir login',
      jiraKey: 'ABC-102',
      jiraStatus: 'Por hacer',
      jiraStatusCategory: 'new',
      accumulatedMs: ms(const Duration(hours: 1, minutes: 5, seconds: 30)),
      timeSinceMs: base.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
    ));
    await repo.insert(Project(
      name: 'Reunión de equipo',
      accumulatedMs: ms(const Duration(minutes: 30)),
      timeSinceMs: base.subtract(const Duration(hours: 4)).millisecondsSinceEpoch,
    ));

    projects = ProjectsController(repo, work: log);
    final store = MemorySecretStore();
    store.data['jira_client_id'] = 'cid';
    store.data['jira_client_secret'] = 'sec';
    store.data['jira_session'] = JiraSessionModel.toJson(JiraSession(
      tokens: TokenSet(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: base.add(const Duration(hours: 1)),
        scope: 'read:jira-work write:jira-work',
      ),
      sites: const [
        JiraSite(id: 's', name: 'Mi empresa', url: 'https://miempresa.atlassian.net'),
      ],
      siteId: 's',
    ));
    jira = JiraController(
      store: store,
      oauth: JiraOAuth(openBrowser: (_) async => false),
      api: JiraApi(),
    );
    await tester.runAsync(() async {
      await projects.load();
      await jira.load();
    });
    daily = DailyController(
      projects,
      log,
      goal: const Duration(hours: 8),
      canPost: () => true,
      post: ({required issueKey, required seconds, required started, comment = ''}) async =>
          null,
    );
    await daily.load();

    const full = Size(520, 600);

    // 1. Pantalla principal
    await pumpApp(tester, full);
    await shot(tester, '01_principal');

    // 2. Agregar un ticket
    await tester.tap(find.byTooltip('Agregar proyecto o ticket'));
    await tester.pumpAndSettle();
    await shot(tester, '02_agregar');
    await tester.tapAt(const Offset(5, 5)); // cierra tocando fuera
    await tester.pumpAndSettle();

    // 3. Corte a Jira de un ticket
    await tester.tap(find.byTooltip('Cortar y enviar a Jira').first);
    await tester.pumpAndSettle();
    await shot(tester, '03_corte_ticket');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // 4. Corte del día
    await tester.tap(find.byTooltip(DayProgressBar.cutTooltip));
    await tester.pumpAndSettle();
    await shot(tester, '04_corte_dia');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // 5. Jira
    await tester.tap(find.byTooltip('Jira'));
    await tester.pumpAndSettle();
    await shot(tester, '05_jira');
    await tester.tap(find.text('Cerrar').last);
    await tester.pumpAndSettle();

    // 6. Ventana (transparencia, superposición, confirmar al cerrar)
    await tester.tap(find.byTooltip('Ventana: transparencia y superposición'));
    await tester.pumpAndSettle();
    await shot(tester, '06_ventana');
    await tester.tap(find.text('Cerrar').last);
    await tester.pumpAndSettle();

    // 9. Filtros de la lista
    await tester.tap(find.byTooltip('Filtros'));
    await tester.pumpAndSettle();
    await shot(tester, '09_filtros');
    await tester.tap(find.text('Cerrar').last);
    await tester.pumpAndSettle();

    // 7. Confirmar al cerrar (con un ticket en curso)
    window.requestClose();
    await tester.pumpAndSettle();
    await shot(tester, '07_cerrar');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    // 8. Vista simple
    await tester.tap(find.byTooltip(HomePage.compactTooltip));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(300, 150) * _ratio;
    await tester.pumpAndSettle();
    await shot(tester, '08_vista_simple');

    await tester.pumpWidget(const SizedBox());
    daily.dispose();
    projects.dispose();
  });
}
