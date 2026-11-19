import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pruebas de arquitectura: hacen cumplir la dirección de las dependencias entre
/// las capas de `lib/` (ver `docs/architecture.md`). Si una de estas falla, un
/// archivo está importando algo de una capa que no le corresponde.
///
///     presentation ──► domain ◄── data
///         │               ▲         │
///         └──► widgets ───┘         │
///     config / core: base común, no dependen de las capas de arriba
///
/// Regla de oro: **`domain` no depende de nada** (ni Flutter, ni SQLite, ni HTTP).
void main() {
  const pkg = 'package:gestion_time_proyect/';

  /// Imports de un archivo: devuelve las rutas internas (`domain/...`) y los
  /// paquetes externos (`package:flutter/...`, `dart:...`) por separado.
  ({List<String> internal, List<String> external}) importsOf(File f) {
    final internal = <String>[], external = <String>[];
    final re = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');
    for (final line in f.readAsLinesSync()) {
      final m = re.firstMatch(line);
      if (m == null) continue;
      final target = m.group(1)!;
      if (target.startsWith(pkg)) {
        internal.add(target.substring(pkg.length));
      } else if (!target.startsWith('.') && !target.contains('/')) {
        external.add(target);
      } else if (target.startsWith('package:') || target.startsWith('dart:')) {
        external.add(target);
      } else {
        // import relativo: en esta base de código todos son de paquete.
        internal.add('RELATIVO:$target');
      }
    }
    return (internal: internal, external: external);
  }

  List<File> filesIn(String dir) => Directory('lib/$dir')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  String rel(File f) => f.path.replaceAll('\\', '/');

  /// Falla si algún archivo de `dir` importa algo de `forbidden` (internos) o de
  /// `forbiddenExternal` (paquetes).
  void expectNoImports(
    String dir, {
    List<String> forbidden = const [],
    List<String> forbiddenExternal = const [],
    String? why,
  }) {
    final offenders = <String>[];
    for (final f in filesIn(dir)) {
      final imp = importsOf(f);
      for (final i in imp.internal) {
        if (forbidden.any(i.startsWith)) offenders.add('${rel(f)} importa $i');
      }
      for (final e in imp.external) {
        if (forbiddenExternal.any(e.startsWith)) offenders.add('${rel(f)} importa $e');
      }
    }
    expect(offenders, isEmpty, reason: why);
  }

  test('en lib/ todos los imports internos son de paquete (rutas absolutas)', () {
    // En lib/ los imports relativos ('../x.dart') esconden en qué capa vive cada
    // archivo y hacen que mover un archivo rompa a sus vecinos. (En test/ se permiten
    // para los archivos de apoyo de `test/support`.)
    final relative = [
      for (final f in filesIn(''))
        if (importsOf(f).internal.any((i) => i.startsWith('RELATIVO:'))) rel(f),
    ];
    expect(relative, isEmpty, reason: 'usa package:gestion_time_proyect/... siempre');
  });

  group('domain: la capa más interna no depende de nada', () {
    test('no importa Flutter ni paquetes de terceros (solo dart:core y dart:math…)', () {
      final offenders = <String>[];
      for (final f in filesIn('domain')) {
        for (final e in importsOf(f).external) {
          if (e.startsWith('package:')) offenders.add('${rel(f)} importa $e');
        }
      }
      expect(offenders, isEmpty,
          reason: 'domain es Dart puro: nada de package:flutter, sqflite, http…');
    });

    test('no importa data, presentation, widgets, config ni core', () {
      expectNoImports('domain',
          forbidden: ['data/', 'presentation/', 'widgets/', 'config/', 'core/'],
          why: 'el dominio no conoce a las capas que lo usan');
    });

    test('no usa dart:io ni dart:ui', () {
      expectNoImports('domain',
          forbiddenExternal: ['dart:io', 'dart:ui'],
          why: 'el dominio no toca el sistema ni la interfaz');
    });
  });

  group('data: implementa los contratos del dominio', () {
    test('no importa presentation ni widgets', () {
      expectNoImports('data',
          forbidden: ['presentation/', 'widgets/'],
          why: 'los datos no saben quién los pinta');
    });

    test('no importa Flutter material/widgets', () {
      expectNoImports('data',
          forbiddenExternal: [
            'package:flutter/material.dart',
            'package:flutter/widgets.dart',
          ],
          why: 'la capa de datos no dibuja nada');
    });
  });

  group('presentation/viewModels: estado sin interfaz', () {
    test('no importan widgets ni Material', () {
      expectNoImports('presentation/viewModels',
          forbidden: ['widgets/', 'presentation/screens/'],
          forbiddenExternal: [
            'package:flutter/material.dart',
            'package:flutter/widgets.dart',
          ],
          why: 'un view model no sabe dibujar; solo guarda estado y notifica');
    });
  });

  group('widgets: el UI kit es reutilizable', () {
    test('no depende de pantallas, view models ni datos', () {
      expectNoImports('widgets',
          forbidden: ['presentation/', 'data/', 'domain/usecases/'],
          why: 'un componente del kit no conoce la lógica de la app');
    });
  });

  group('config y core: base común', () {
    test('config no depende de presentation, data ni domain', () {
      expectNoImports('config',
          forbidden: ['presentation/', 'data/', 'domain/'],
          why: 'config solo define tema y rutas');
    });

    test('core no depende de presentation ni de widgets', () {
      expectNoImports('core',
          forbidden: ['presentation/', 'widgets/'],
          why: 'core es la base de la que dependen las demás capas');
    });
  });
}
