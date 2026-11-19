import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/data/datasources/jira_api.dart';
import 'package:gestion_time_proyect/data/datasources/jira_oauth.dart';
import 'package:gestion_time_proyect/data/datasources/secret_store.dart';
import 'package:gestion_time_proyect/presentation/screens/compact_view.dart';
import 'package:gestion_time_proyect/presentation/screens/home_page.dart';
import 'package:gestion_time_proyect/presentation/viewModels/daily_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';

import '../support/fakes.dart';

void main() {
  late FakeProjectsRepository repo;
  late ProjectsController controller;

  setUp(() async {
    repo = FakeProjectsRepository();
    controller = ProjectsController(repo);
    await controller.load();
  });

  /// `testWidgets` con una salvedad: el controlador crea un `Timer` periódico
  /// mientras hay un cronómetro en marcha, y Flutter exige que no quede ninguno
  /// pendiente al terminar el *cuerpo* de la prueba (antes de los `tearDown`).
  /// Por eso el controlador se libera aquí, al final del cuerpo.
  void widgetTest(String name, Future<void> Function(WidgetTester tester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        controller.dispose();
      }
    });
  }

  /// Contenido de la vista simple: la ventana compacta menos la barra de título del
  /// sistema (~31 px), que no es de Flutter.
  Size compactContent() =>
      Size(WindowLimits.compact.width, WindowLimits.compact.height - 31);

  Future<void> pumpCompact(
    WidgetTester tester, {
    VoidCallback? onExit,
    Size? size,
  }) async {
    tester.view.physicalSize = size ?? compactContent();
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: CompactView(controller: controller, onExit: onExit ?? () {}),
    ));
    await tester.pump();
  }

  Future<void> addRunning(String name) async {
    await controller.add(name, '', '');
    await controller.start(controller.projects.last);
  }

  group('contenido', () {
    widgetTest('muestra solo el ticket en curso: su nombre y su tiempo', (tester) async {
      await controller.add('Otro ticket parado', '', '');
      await addRunning('ABC-12 Revisar el flujo de pagos');
      await pumpCompact(tester);

      expect(find.text('ABC-12 Revisar el flujo de pagos'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\d\d:\d\d:\d\d$')), findsOneWidget);
      expect(find.text('Otro ticket parado'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    widgetTest('sin ticket en curso la vista no tiene sentido: sale sola', (tester) async {
      await controller.add('Parado', '', '');
      var exits = 0;
      await pumpCompact(tester, onExit: () => exits++);
      await tester.pump(); // el aviso de salida se da tras el primer cuadro

      expect(exits, 1);
    });

    widgetTest('si el ticket deja de correr estando en la vista, sale sola y una sola vez',
        (tester) async {
      await addRunning('ABC-12 algo');
      var exits = 0;
      await pumpCompact(tester, onExit: () => exits++);
      expect(exits, 0);

      await controller.pause(controller.projects.single);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2)); // el cronómetro ya no corre

      expect(exits, 1);
    });

    widgetTest('es de solo lectura: lo único que se puede pulsar es la salida', (tester) async {
      await addRunning('ABC-12 algo');
      await pumpCompact(tester);

      expect(find.byType(IconButton), findsOneWidget);
      expect(find.byTooltip(CompactView.exitTooltip), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget); // la transparencia de esta vista
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    widgetTest('el nombre ocupa una sola línea y se recorta con puntos suspensivos',
        (tester) async {
      await addRunning('ABC-12 ${'nombre larguísimo ' * 12}');
      await pumpCompact(tester);

      final name = tester.widget<Text>(find.textContaining('ABC-12'));
      expect(name.maxLines, CompactLimits.nameMaxLines);
      expect(name.overflow, TextOverflow.ellipsis);
    });

    widgetTest('cabe en la ventana compacta sin desbordar (claro y oscuro)', (tester) async {
      await addRunning('ABC-12 ${'nombre larguísimo ' * 12}');
      await pumpCompact(tester);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = compactContent();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: CompactView(controller: controller, onExit: () {}),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    widgetTest('el tiempo es mayor que el de una tarjeta (es lo único que se ve)',
        (tester) async {
      await addRunning('ABC-12 algo');
      await pumpCompact(tester);

      final time = tester.widget<Text>(find.textContaining(RegExp(r'^\d\d:\d\d:\d\d$')));
      expect(time.style!.fontSize, AppFontSize.compactTimer);
      expect(AppFontSize.compactTimer, greaterThan(AppFontSize.timer));
    });
  });

  group('control de transparencia de la vista simple', () {
    Slider slider(WidgetTester tester) => tester.widget<Slider>(find.byType(Slider));

    widgetTest('está siempre visible, con el valor propio de esta vista', (tester) async {
      await addRunning('ABC-12 algo');
      await controller.setCompactOpacity(0.6);
      await pumpCompact(tester);

      expect(find.byType(Slider), findsOneWidget);
      expect(find.byTooltip(CompactView.opacityTooltip), findsOneWidget);
      expect(slider(tester).value, 0.6);
      expect(find.text('60%'), findsOneWidget);
      expect(find.byIcon(AppIcons.opacity), findsOneWidget);
    });

    widgetTest('va del mínimo permitido (30 %) al 100 %', (tester) async {
      await addRunning('ABC-12 algo');
      await pumpCompact(tester);

      expect(slider(tester).min, ProjectsController.minOpacity);
      expect(slider(tester).max, 1.0);
    });

    widgetTest('al arrastrar cambia la transparencia de esta vista y avisa a la ventana',
        (tester) async {
      await addRunning('ABC-12 algo');
      await controller.setOpacity(0.9); // la de la vista completa
      final applied = <double>[];
      tester.view.physicalSize = compactContent();
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: CompactView(controller: controller, onExit: () {}, onOpacity: applied.add),
      ));
      await tester.pump();

      slider(tester).onChanged!(0.5);
      await tester.pump();

      expect(controller.compactOpacity, 0.5);
      expect(controller.opacity, 0.9); // la otra no se mueve
      expect(applied, [0.5]);
      expect(find.text('50%'), findsOneWidget);
    });

    widgetTest('arrastrar no escribe en el repositorio; soltar sí', (tester) async {
      await addRunning('ABC-12 algo');
      await pumpCompact(tester);
      expect(repo.settingWrites['opacity_compact'], isNull);

      slider(tester).onChanged!(0.7);
      await tester.pump();
      expect(repo.settingWrites['opacity_compact'], isNull);

      slider(tester).onChangeEnd!(0.7);
      await tester.pump();
      expect(repo.settings['opacity_compact'], '0.7');
    });

    widgetTest('arrastrar el deslizador de verdad cambia el valor', (tester) async {
      await addRunning('ABC-12 algo');
      await controller.setCompactOpacity(1.0);
      await pumpCompact(tester);

      await tester.drag(find.byType(Slider), const Offset(-80, 0));
      await tester.pump();

      expect(controller.compactOpacity, lessThan(1.0));
      expect(controller.compactOpacity, greaterThanOrEqualTo(ProjectsController.minOpacity));
    });

    widgetTest('tocar el deslizador es inmediato y NO sale de la vista (aunque sea doble toque)',
        (tester) async {
      var exits = 0;
      await addRunning('ABC-12 algo');
      await pumpCompact(tester, onExit: () => exits++);

      await tester.tap(find.byType(Slider));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(Slider));
      await tester.pump(const Duration(seconds: 1));

      expect(exits, 0);
    });

    widgetTest('el deslizador cuenta en la altura que se pide a la ventana', (tester) async {
      await addRunning('ABC-12 algo');
      Size? fit;
      tester.view.physicalSize = const Size(280, 300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: CompactView(controller: controller, onExit: () {}, onFit: (c, _) => fit = c),
      ));
      await tester.pump();

      final sliderBottom = tester.getRect(find.byType(Slider)).bottom;
      final nameTop = tester.getRect(find.textContaining('ABC-12')).top;
      // lo medido cubre desde el nombre hasta el final del deslizador
      expect(fit!.height, greaterThanOrEqualTo(sliderBottom - nameTop));
    });

    widgetTest('el botón de salida responde al instante, sin esperar al doble clic',
        (tester) async {
      var exits = 0;
      await addRunning('ABC-12 algo');
      await pumpCompact(tester, onExit: () => exits++);

      await tester.tap(find.byTooltip(CompactView.exitTooltip));
      await tester.pump(); // sin avanzar el reloj: no hay espera de 300 ms

      expect(exits, 1);
    });
  });

  group('el botón de salida', () {
    widgetTest('está siempre visible y no hace falta conocer el doble clic ni Esc', (tester) async {
      await addRunning('ABC-12 algo');
      await pumpCompact(tester);

      expect(find.byTooltip(CompactView.exitTooltip), findsOneWidget);
      expect(find.byIcon(AppIcons.restoreView), findsOneWidget);
    });

    widgetTest('un solo clic en él vuelve a la vista completa', (tester) async {
      var exits = 0;
      await addRunning('ABC-12 algo');
      await pumpCompact(tester, onExit: () => exits++);

      await tester.tap(find.byTooltip(CompactView.exitTooltip));
      await tester.pump();

      expect(exits, 1);
    });

    widgetTest('cabe en la ventana compacta sin desbordar el contenido', (tester) async {
      await addRunning('ABC-12 ${'nombre larguísimo ' * 12}');
      await pumpCompact(tester);

      expect(tester.takeException(), isNull);
      // el botón no tapa el cronómetro
      final time = tester.getRect(find.textContaining(RegExp(r'^\d\d:\d\d:\d\d$')));
      final button = tester.getRect(find.byTooltip(CompactView.exitTooltip));
      expect(time.right, lessThanOrEqualTo(button.left));
    });

    widgetTest('el nombre largo no pasa por debajo del botón', (tester) async {
      await addRunning('ABC-12 ${'nombre larguísimo ' * 12}');
      await pumpCompact(tester);

      final name = tester.getRect(find.textContaining('ABC-12'));
      final button = tester.getRect(find.byTooltip(CompactView.exitTooltip));
      expect(name.right, lessThanOrEqualTo(button.left));
    });
  });

  group('volver a la vista completa', () {
    widgetTest('doble clic en cualquier parte', (tester) async {
      var exits = 0;
      await addRunning('ABC-12 algo');
      await pumpCompact(tester, onExit: () => exits++);

      await tester.tap(find.textContaining('ABC-12'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.textContaining('ABC-12'));
      await tester.pump();
      expect(exits, 1);
      // deja vencer los plazos del reconocedor de gestos (doble toque)
      await tester.pump(const Duration(seconds: 1));
    });

    widgetTest('un solo clic no sale (evita salir por accidente)', (tester) async {
      var exits = 0;
      await addRunning('ABC-12 algo');
      await pumpCompact(tester, onExit: () => exits++);

      await tester.tap(find.textContaining('ABC-12'));
      await tester.pump(const Duration(seconds: 1));
      expect(exits, 0);
    });

    widgetTest('tecla Esc', (tester) async {
      var exits = 0;
      await addRunning('ABC-12 algo');
      await pumpCompact(tester, onExit: () => exits++);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(exits, 1);
    });

    widgetTest('otras teclas no salen', (tester) async {
      var exits = 0;
      await addRunning('ABC-12 algo');
      await pumpCompact(tester, onExit: () => exits++);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(exits, 0);
    });

    widgetTest('explica cómo volver con un aviso al pasar el cursor', (tester) async {
      await addRunning('ABC-12 algo');
      await pumpCompact(tester);

      final tip = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .firstWhere((t) => t.message == CompactView.hint);
      expect(tip.message, CompactView.hint);
      expect(CompactView.hint, contains('Doble clic'));
      expect(CompactView.hint, contains('Esc'));
    });
  });

  group('ajuste automático del tamaño', () {
    /// La columna con el nombre y el tiempo (el contenido que debe caber).
    Finder content() => find.byWidgetPredicate(
        (w) => w is Column && w.mainAxisSize == MainAxisSize.min && w.children.length == 2);

    widgetTest('informa la altura natural del contenido y el tamaño de su área', (tester) async {
      await addRunning('ABC-12 algo');
      final fits = <({Size content, Size client})>[];
      tester.view.physicalSize = const Size(280, 120);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: CompactView(
          controller: controller,
          onExit: () {},
          onFit: (c, k) => fits.add((content: c, client: k)),
        ),
      ));
      await tester.pump();

      expect(fits, isNotEmpty);
      final natural = tester.getSize(content().first).height;
      expect(fits.last.content.height, natural + 2 * CompactView.verticalPadding);
      expect(fits.last.content.width, WindowLimits.compact.width);
      expect(fits.last.client, const Size(280, 120));
    });

    widgetTest('si la ventana es más baja que el contenido, lo mide igual y no desborda',
        (tester) async {
      await addRunning('ABC-12 algo');
      Size? reported;
      tester.view.physicalSize = const Size(280, 30); // mucho menos de lo necesario
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: CompactView(controller: controller, onExit: () {}, onFit: (c, _) => reported = c),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull); // sin RenderFlex overflow
      expect(reported!.height, greaterThan(30)); // sabe que necesita más
    });

    widgetTest('sin ticket en curso pide menos alto que con uno', (tester) async {
      await controller.add('Parado', '', '');
      final heights = <double>[];
      tester.view.physicalSize = const Size(280, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: CompactView(
            controller: controller, onExit: () {}, onFit: (c, _) => heights.add(c.height)),
      ));
      await tester.pump();
      final empty = heights.last;

      // Arranca un ticket: el contenido crece (nombre + tiempo) y se vuelve a ajustar.
      await controller.start(controller.projects.single);
      await tester.pump();
      await tester.pump();

      expect(heights.last, greaterThan(empty));
    });

    widgetTest('al cambiar el tamaño de la ventana vuelve a comprobar el ajuste', (tester) async {
      await addRunning('ABC-12 algo');
      final fits = <({Size content, Size client})>[];
      tester.view.physicalSize = const Size(280, 100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: CompactView(
            controller: controller,
            onExit: () {},
            onFit: (c, k) => fits.add((content: c, client: k))),
      ));
      await tester.pump();
      final before = fits.length;

      // La ventana se reajustó: el área cambia, el contenido es el mismo.
      tester.view.physicalSize = const Size(280, 140);
      await tester.pump();
      await tester.pump();

      expect(fits.length, greaterThan(before));
      expect(fits.last.client, const Size(280, 140));
      expect(fits.last.content.height, fits.first.content.height);
    });

    widgetTest('sin onFit funciona igual (no hay nadie que ajuste la ventana)', (tester) async {
      await addRunning('ABC-12 algo');
      await pumpCompact(tester);
      expect(tester.takeException(), isNull);
    });

    widgetTest('mientras el cronómetro corre no repite el aviso si nada cambió', (tester) async {
      await addRunning('ABC-12 algo');
      var calls = 0;
      tester.view.physicalSize = const Size(280, 120);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: CompactView(controller: controller, onExit: () {}, onFit: (_, _) => calls++),
      ));
      await tester.pump();
      final first = calls;

      // Pasan varios segundos: el tiempo cambia cada segundo, el tamaño no.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(calls, first);
    });
  });

  group('integración con la pantalla principal', () {
    late FakeWindowService window;
    late JiraController jira;
    late DailyController daily;

    setUp(() {
      window = FakeWindowService();
      daily = DailyController(controller, FakeWorkLogRepository(),
          goal: const Duration(hours: 8));
      addTearDown(daily.dispose);
      jira = JiraController(
        store: MemorySecretStore(),
        oauth: JiraOAuth(openBrowser: (_) async => false),
        api: JiraApi(),
      );
    });

    const pinTooltip = 'Vista simple: solo el ticket en curso';

    Future<void> pumpHome(WidgetTester tester) async {
      tester.view.physicalSize = WindowLimits.min;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: HomePage(controller: controller, jira: jira, daily: daily, window: window),
      ));
      await tester.pump();
    }

    widgetTest('el pin abre la vista simple y encoge la ventana con su transparencia',
        (tester) async {
      await addRunning('ABC-12 Pagos');
      await controller.setCompactOpacity(0.6);
      await pumpHome(tester);

      expect(find.byType(AppBar), findsOneWidget);
      await tester.tap(find.byTooltip(pinTooltip));
      await tester.pump();

      expect(controller.compactMode, isTrue);
      expect(find.byType(CompactView), findsOneWidget);
      expect(find.byType(AppBar), findsNothing); // no queda nada de la vista completa
      expect(window.calls.where((c) => !c.startsWith('fitCompact')), ['enterCompact:0.60']);
      // y la ventana simple se ajusta a su contenido
      expect(window.lastFit, isNotNull);
      expect(window.lastFit!.content.width, WindowLimits.compact.width);
    });

    widgetTest('doble clic vuelve: restaura la transparencia y superposición de la vista completa',
        (tester) async {
      await addRunning('ABC-12 Pagos');
      await controller.setOpacity(0.9);
      await controller.setAlwaysOnTop(true);
      await controller.setCompactOpacity(0.5);
      await pumpHome(tester);

      await tester.tap(find.byTooltip(pinTooltip));
      await tester.pump();
      await tester.tap(find.textContaining('ABC-12'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.textContaining('ABC-12'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1)); // plazos del doble toque

      expect(window.calls.where((c) => !c.startsWith('fitCompact')),
          ['enterCompact:0.50', 'exitCompact:0.90:true']);
      expect(controller.compactMode, isFalse);
      expect(find.byType(CompactView), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
    });

    widgetTest('Esc también vuelve', (tester) async {
      await addRunning('ABC-12 Pagos');
      await pumpHome(tester);

      await tester.tap(find.byTooltip(pinTooltip));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(controller.compactMode, isFalse);
      expect(window.calls.last, startsWith('exitCompact'));
    });

    widgetTest('el tiempo sigue corriendo en la vista simple y al volver', (tester) async {
      await addRunning('ABC-12 Pagos');
      final startedAt = controller.projects.single.startedAtMs;
      await pumpHome(tester);

      await tester.tap(find.byTooltip(pinTooltip));
      await tester.pump();
      expect(controller.projects.single.isRunning, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(controller.projects.single.isRunning, isTrue);
      expect(controller.projects.single.startedAtMs, startedAt); // ni se reinició ni se pausó
    });

    widgetTest('sin ticket en curso el pin está desactivado y explica por qué', (tester) async {
      await controller.add('Parado', '', '');
      await pumpHome(tester);

      final button = tester.widget<IconButton>(find.ancestor(
        of: find.byTooltip(HomePage.compactDisabledTooltip),
        matching: find.byType(IconButton),
      ).first);
      // (el Tooltip envuelve al botón: se busca el IconButton que lo contiene)
      expect(find.byTooltip(HomePage.compactDisabledTooltip), findsOneWidget);
      expect(find.byTooltip(HomePage.compactTooltip), findsNothing);

      await tester.tap(find.byTooltip(HomePage.compactDisabledTooltip), warnIfMissed: false);
      await tester.pump();

      expect(button.onPressed, isNull);
      expect(controller.compactMode, isFalse);
      expect(window.calls, isEmpty); // la ventana ni se enteró
      expect(find.byType(CompactView), findsNothing);
    });

    widgetTest('con un ticket parado el pin tampoco está activo', (tester) async {
      await controller.add('Parado', '', '');
      await controller.start(controller.projects.single);
      await controller.pause(controller.projects.single);
      await pumpHome(tester);

      expect(find.byTooltip(HomePage.compactDisabledTooltip), findsOneWidget);
    });

    widgetTest('al iniciar un ticket el pin se activa', (tester) async {
      await controller.add('A', '', '');
      await pumpHome(tester);
      expect(find.byTooltip(HomePage.compactDisabledTooltip), findsOneWidget);

      await controller.start(controller.projects.single);
      await tester.pump();

      expect(find.byTooltip(HomePage.compactTooltip), findsOneWidget);
      expect(find.byTooltip(HomePage.compactDisabledTooltip), findsNothing);
    });

    widgetTest('el botón de la esquina vuelve a la vista completa', (tester) async {
      await addRunning('ABC-12 Pagos');
      await pumpHome(tester);

      await tester.tap(find.byTooltip(pinTooltip));
      await tester.pump();
      expect(controller.compactMode, isTrue);

      await tester.tap(find.byTooltip(CompactView.exitTooltip));
      await tester.pump();

      expect(controller.compactMode, isFalse);
      expect(find.byType(AppBar), findsOneWidget);
      expect(window.calls.last, startsWith('exitCompact'));
    });

    widgetTest('si la ventana nativa falla al volver, la interfaz no se queda atrapada',
        (tester) async {
      await addRunning('ABC-12 Pagos');
      window.throwOnExit = true;
      await pumpHome(tester);

      await tester.tap(find.byTooltip(pinTooltip));
      await tester.pump();
      expect(find.byType(CompactView), findsOneWidget);

      await tester.tap(find.byTooltip(CompactView.exitTooltip));
      await tester.pump();
      await tester.pump();

      expect(controller.compactMode, isFalse); // salió igual
      expect(find.byType(CompactView), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      expect(tester.takeException(), isNull); // el fallo se registró, no se propagó
    });

    widgetTest('si el ticket se pausa estando en la vista simple, la pantalla vuelve sola',
        (tester) async {
      await addRunning('ABC-12 Pagos');
      await pumpHome(tester);

      await tester.tap(find.byTooltip(pinTooltip));
      await tester.pump();
      expect(find.byType(CompactView), findsOneWidget);

      await controller.pause(controller.projects.single);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(controller.compactMode, isFalse);
      expect(find.byType(CompactView), findsNothing);
      expect(window.calls.where((c) => c.startsWith('exitCompact')).length, 1);
    });

    widgetTest('las dos transparencias se manejan por separado en el diálogo de ventana',
        (tester) async {
      await pumpHome(tester);

      await tester.tap(find.byTooltip('Ventana: transparencia y superposición'));
      await tester.pumpAndSettle();
      final sliders = find.byType(Slider);
      expect(sliders, findsNWidgets(2));

      // Vista completa: se aplica a la ventana al instante.
      tester.widget<Slider>(sliders.at(0)).onChanged!(0.7);
      await tester.pump();
      expect(controller.opacity, 0.7);
      expect(window.lastOpacity, 0.7);

      // Vista simple: solo se guarda; la ventana (que está en la vista completa) no cambia.
      window.calls.clear();
      tester.widget<Slider>(sliders.at(1)).onChanged!(0.4);
      await tester.pump();
      expect(controller.compactOpacity, 0.4);
      expect(controller.opacity, 0.7); // la otra no se movió
      expect(window.calls, isEmpty);
    });

    widgetTest('el interruptor de superposición aplica a la ventana y se guarda', (tester) async {
      await pumpHome(tester);

      await tester.tap(find.byTooltip('Ventana: transparencia y superposición'));
      await tester.pumpAndSettle();
      // En la app real el diálogo agranda la ventana (`showFittedDialog`); aquí se simula.
      tester.view.physicalSize = const Size(360, 800);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mantener encima de otras ventanas'));
      await tester.pump();

      expect(controller.alwaysOnTop, isTrue);
      expect(window.calls, contains('alwaysOnTop:true'));
      expect(repo.settings['always_on_top'], '1');
    });
  });
}
