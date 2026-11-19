import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/widgets/widgets.dart';

/// Monta `child` con el tema real de la app, en una ventana de `size`.
Future<void> pumpKit(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(360, 400),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    home: Scaffold(body: Center(child: child)),
  ));
  // Si el tema cambió respecto a una carga anterior, Flutter lo anima (200 ms): se
  // deja terminar para medir los colores finales y no los de mitad de transición.
  await tester.pumpAndSettle();
}

void main() {
  group('límites', () {
    test('en la ventana mínima la etiqueta de estado dispone de su ancho mínimo', () {
      // [play][cronómetro][— etiqueta —][limpiar][cortar][info]
      final slot = TileLimits.statusSlotWidth(WindowLimits.min.width);
      expect(slot, greaterThanOrEqualTo(TileLimits.statusSlotMinWidth),
          reason: 'los elementos fijos de la tarjeta se comen el hueco de la etiqueta');
    });

    test('un ticket manual (una acción menos) tiene aún más hueco', () {
      expect(TileLimits.statusSlotWidth(WindowLimits.min.width, actions: 2),
          greaterThan(TileLimits.statusSlotWidth(WindowLimits.min.width)));
    });

    test('la ventana mínima es el 120 % de ancho y el 110 % de alto de 300×220', () {
      expect(WindowLimits.min.width, closeTo(300 * 1.2, 0.001));
      expect(WindowLimits.min.height, closeTo(220 * 1.1, 0.001));
    });

    test('los diálogos caben en la ventana mínima y el detalle admite más', () {
      expect(DialogLimits.formWidth, lessThan(WindowLimits.min.width));
      expect(DialogLimits.compactWidth, lessThan(DialogLimits.formWidth));
      expect(DialogLimits.infoMaxWidth, greaterThan(DialogLimits.formWidth));
    });

    test('los tamaños de botón van de menor a mayor', () {
      expect(AppIconButtonSize.compact.box, lessThan(AppIconButtonSize.regular.box));
      expect(AppIconButtonSize.regular.box, lessThan(AppIconButtonSize.large.box));
      for (final s in AppIconButtonSize.values) {
        expect(s.icon, lessThan(s.box)); // el icono siempre cabe en su botón
      }
    });
  });

  group('AppIconButton', () {
    testWidgets('mide lo que dice su tamaño y muestra el tooltip', (tester) async {
      for (final size in AppIconButtonSize.values) {
        await pumpKit(
          tester,
          AppIconButton(
              icon: AppIcons.info, tooltip: 'Info ${size.name}', size: size, onPressed: () {}),
        );
        final box = tester.getSize(find.byTooltip('Info ${size.name}'));
        expect(box, Size.square(size.box), reason: size.name);
      }
    });

    testWidgets('onPressed null lo deshabilita', (tester) async {
      var taps = 0;
      await pumpKit(tester,
          AppIconButton(icon: AppIcons.add, tooltip: 'Agregar', onPressed: () => taps++));
      await tester.tap(find.byTooltip('Agregar'));
      expect(taps, 1);

      await pumpKit(
          tester, const AppIconButton(icon: AppIcons.add, tooltip: 'Agregar', onPressed: null));
      await tester.tap(find.byTooltip('Agregar'), warnIfMissed: false);
      expect(taps, 1);
    });

    testWidgets('los botones rellenos conservan su color dentro de una AppBar', (tester) async {
      tester.view.physicalSize = const Size(360, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          appBar: AppBar(actions: [
            AppIconButton(
              icon: AppIcons.add,
              variant: AppIconButtonVariant.filled,
              tooltip: 'Agregar',
              onPressed: () {},
            ),
          ]),
        ),
      ));
      final scheme = AppTheme.dark().colorScheme;
      final icon = tester.widget<Icon>(find.descendant(
          of: find.byTooltip('Agregar'), matching: find.byType(Icon)));
      final iconColor = IconTheme.of(tester.element(find.byIcon(AppIcons.add))).color;
      // El icono no debe heredar el color de la AppBar: debe ser el "onPrimary".
      expect(icon.icon, AppIcons.add);
      expect(iconColor, isNot(scheme.onSurfaceVariant));
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.style!.foregroundColor!.resolve({}), scheme.onPrimary);
      expect(button.style!.backgroundColor!.resolve({}), scheme.primary);
    });

    testWidgets('el modo seleccionado cambia de icono', (tester) async {
      await pumpKit(
        tester,
        AppIconButton(
          icon: AppIcons.pin,
          selectedIcon: AppIcons.pinActive,
          selected: true,
          tooltip: 'Pin',
          onPressed: () {},
        ),
      );
      expect(find.byIcon(AppIcons.pinActive), findsOneWidget);
      expect(find.byIcon(AppIcons.pin), findsNothing);
    });
  });

  group('AppTextField', () {
    testWidgets('el campo normal muestra su etiqueta y valida', (tester) async {
      final c = TextEditingController();
      final key = GlobalKey<FormState>();
      await pumpKit(
        tester,
        SizedBox(
          width: DialogLimits.formWidth,
          child: Form(
            key: key,
            child: AppTextField(
              controller: c,
              label: 'Nombre',
              validator: (v) => (v ?? '').isEmpty ? 'Requerido' : null,
            ),
          ),
        ),
      );
      expect(find.text('Nombre'), findsOneWidget);
      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Requerido'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'algo');
      expect(key.currentState!.validate(), isTrue);
    });

    testWidgets('digits solo admite dígitos y respeta el máximo', (tester) async {
      final c = TextEditingController();
      await pumpKit(
        tester,
        SizedBox(
          width: 80,
          child: AppTextField.digits(controller: c, label: 'min', maxLength: 2),
        ),
      );
      await tester.enterText(find.byType(TextField), 'a1b2c3');
      expect(c.text, '12'); // sin letras y recortado a 2 dígitos
    });

    testWidgets('multiline limita las líneas al tope del kit', (tester) async {
      final c = TextEditingController();
      await pumpKit(
        tester,
        SizedBox(
          width: DialogLimits.formWidth,
          child: AppTextField.multiline(controller: c, label: 'Texto', maxLines: 99),
        ),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).maxLines,
          FieldLimits.maxLinesCap);

      await pumpKit(
        tester,
        SizedBox(
          width: DialogLimits.formWidth,
          child: AppTextField.multiline(controller: c, label: 'Texto'),
        ),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).maxLines,
          FieldLimits.multilineDefault);
    });

    testWidgets('secret oculta lo escrito', (tester) async {
      await pumpKit(
        tester,
        SizedBox(
          width: DialogLimits.formWidth,
          child: AppTextField.secret(
              controller: TextEditingController(), label: 'Secreto'),
        ),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
    });
  });

  group('AppChip', () {
    testWidgets('no pasa de su ancho máximo y recorta con puntos suspensivos', (tester) async {
      await pumpKit(
        tester,
        const AppChip(label: 'Un estado larguísimo que no cabe en el hueco', maxWidth: 90),
      );
      expect(tester.getSize(find.byType(AppChip)).width, lessThanOrEqualTo(90));
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.maxLines, ChipLimits.maxLines);
    });

    testWidgets('nunca supera el tope absoluto aunque se pida más', (tester) async {
      await pumpKit(
        tester,
        SizedBox(
          width: 1000,
          // Align suelta la restricción: en una fila real el hueco es acotado, no fijo.
          child: Align(
            alignment: Alignment.centerLeft,
            child: AppChip(label: 'x' * 400, maxWidth: 9999),
          ),
        ),
        size: const Size(1100, 300),
      );
      expect(tester.getSize(find.byType(AppChip)).width, lessThanOrEqualTo(ChipLimits.maxWidth));
    });

    testWidgets('se adapta al hueco de una fila sin desbordar', (tester) async {
      await pumpKit(
        tester,
        SizedBox(
          width: 120,
          child: Row(children: [
            const Text('00:00:00'),
            const Expanded(
              child: Center(child: AppChip(label: 'Esperando revisión de QA')),
            ),
          ]),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('el tooltip por defecto es el texto completo', (tester) async {
      await pumpKit(tester, const AppChip(label: 'En curso'));
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'En curso');

      await pumpKit(tester, const AppChip(label: 'En curso', tooltip: 'Estado en Jira: En curso'));
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'Estado en Jira: En curso');
    });

    testWidgets('el icono solo se dibuja en la variante soft', (tester) async {
      await pumpKit(
        tester,
        const AppChip(label: 'a', variant: AppChipVariant.soft, icon: AppIcons.timer),
      );
      expect(find.byIcon(AppIcons.timer), findsOneWidget);

      await pumpKit(
        tester,
        const AppChip(label: 'a', variant: AppChipVariant.badge, icon: AppIcons.timer),
      );
      expect(find.byIcon(AppIcons.timer), findsNothing);
    });

    testWidgets('cada tono produce un color de texto distinto y legible en claro y oscuro',
        (tester) async {
      for (final brightness in Brightness.values) {
        final fgs = <Color>{};
        for (final tone in AppChipTone.values) {
          await pumpKit(tester, AppChip(label: 'x', tone: tone), brightness: brightness);
          final color = tester.widget<Text>(find.text('x')).style!.color!;
          fgs.add(color);
          // Contraste del texto frente al fondo REAL de la etiqueta: su relleno
          // teñido, puesto sobre el fondo de la ventana.
          final surface = (brightness == Brightness.dark
                  ? AppTheme.dark()
                  : AppTheme.light())
              .colorScheme
              .surface;
          final box = tester
              .widget<Container>(find
                  .descendant(of: find.byType(AppChip), matching: find.byType(Container))
                  .first)
              .decoration as BoxDecoration;
          final bg = Color.alphaBlend(box.color!, surface);
          final ratio = _contrast(color, bg);
          expect(ratio, greaterThan(3.0),
              reason: '${tone.name} en ${brightness.name}: $ratio fg=$color bg=$bg box=${box.color}');
        }
        expect(fgs.length, greaterThanOrEqualTo(4), reason: brightness.name);
      }
    });
  });

  group('AppPanel, AppSectionLabel, AppEmptyState, AppDialogBody', () {
    testWidgets('AppSectionLabel pone el texto en mayúsculas', (tester) async {
      await pumpKit(tester, const AppSectionLabel('Descripción'));
      expect(find.text('DESCRIPCIÓN'), findsOneWidget);
    });

    testWidgets('AppPanel ocupa todo el ancho y responde al toque', (tester) async {
      var taps = 0;
      await pumpKit(
        tester,
        SizedBox(
          width: 300,
          child: AppPanel(
            variant: AppPanelVariant.outlined,
            onTap: () => taps++,
            child: const Text('enlace'),
          ),
        ),
      );
      expect(tester.getSize(find.byType(AppPanel)).width, 300);
      await tester.tap(find.text('enlace'));
      expect(taps, 1);
    });

    testWidgets('AppEmptyState muestra la acción y la dispara', (tester) async {
      var taps = 0;
      await pumpKit(
        tester,
        AppEmptyState(
          icon: AppIcons.timer,
          title: 'Vacío',
          message: 'Nada por aquí',
          actionLabel: 'Agregar',
          actionIcon: AppIcons.add,
          onAction: () => taps++,
        ),
        size: const Size(360, 242),
      );
      expect(find.text('Vacío'), findsOneWidget);
      await tester.tap(find.text('Agregar'));
      expect(taps, 1);
      expect(tester.takeException(), isNull); // cabe en la ventana mínima
    });

    testWidgets('AppEmptyState sin acción no dibuja botón', (tester) async {
      await pumpKit(
        tester,
        const AppEmptyState(icon: AppIcons.timer, title: 'Vacío', message: 'Nada'),
      );
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('AppDialogBody fija el ancho y hace scroll si el contenido es alto',
        (tester) async {
      await pumpKit(
        tester,
        SizedBox(
          height: 150,
          child: AppDialogBody(
            child: Column(children: [for (var i = 0; i < 30; i++) Text('línea $i')]),
          ),
        ),
        size: const Size(360, 242),
      );
      expect(tester.getSize(find.byType(AppDialogBody)).width, DialogLimits.formWidth);
      expect(tester.takeException(), isNull); // sin desborde: hace scroll
    });
  });

  group('centralización: nadie se salta el kit', () {
    /// Todos los archivos de `lib/`, con ruta normalizada (`lib/a/b.dart`).
    List<File> sources() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    String norm(File f) => f.path.replaceAll('\\', '/');

    String code(File f) => f
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    /// Falla si `pattern` aparece en algún archivo fuera de las rutas `allowed`.
    void expectOnlyIn(RegExp pattern, List<String> allowed, String what) {
      final offenders = [
        for (final f in sources())
          if (!allowed.any(norm(f).startsWith) && pattern.hasMatch(code(f))) norm(f),
      ];
      expect(offenders, isEmpty,
          reason: '$what: solo puede usarse en ${allowed.join(' o ')}; '
              'en el resto de la app, usa el componente del kit');
    }

    test('los iconos salen de AppIcons, no de Icons.*', () {
      expectOnlyIn(RegExp(r'\bIcons\.'), ['lib/config/theme/app_icons.dart'], 'Icons.*');
    });

    test('los botones de icono son AppIconButton', () {
      expectOnlyIn(RegExp(r'\bIconButton\b'), ['lib/widgets/buttons/'], 'IconButton');
    });

    test('los campos de texto son AppTextField', () {
      expectOnlyIn(RegExp(r'\bTextFormField\(|\bTextField\('), ['lib/widgets/inputs/'],
          'TextField');
    });

    test('la decoración de campos vive en el tema y en los inputs', () {
      expectOnlyIn(RegExp(r'\bInputDecoration\('),
          ['lib/widgets/inputs/', 'lib/config/theme/'], 'InputDecoration');
    });

    test('el tema y los colores propios se definen en config/theme', () {
      expectOnlyIn(RegExp(r'\bThemeData\('), ['lib/config/theme/'], 'ThemeData');
      expectOnlyIn(RegExp(r'\bColor\(0x'), ['lib/config/theme/'], 'colores fijos');
    });
  });
}

/// Relación de contraste WCAG entre dos colores.
double _contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final la = lum(a), lb = lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
