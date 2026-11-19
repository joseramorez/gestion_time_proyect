import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/core/services/window_service.dart';

/// La cuenta que decide el alto de la ventana simple. Es lo que falló en un equipo con
/// la barra de título más alta: con una cifra fija, el contenido no cabía por 2 px.
void main() {
  group('compactWindowHeight', () {
    test('suma al contenido lo que ocupan la barra de título y los bordes', () {
      // Ventana de 100 con 61 de área: la barra y los bordes ocupan 39.
      expect(
        compactWindowHeight(outerHeight: 100, clientHeight: 61, contentHeight: 63),
        102, // 63 + 39 — justo lo que faltaba (el contenido pedía 2 px más)
      );
    });

    test('se adapta a otro equipo donde la barra de título ocupa menos', () {
      // Misma ventana de 100, pero aquí el área es de 69: la barra ocupa 31.
      expect(
        compactWindowHeight(outerHeight: 100, clientHeight: 69, contentHeight: 63),
        94,
      );
    });

    test('converge: con la ventana ya ajustada, pedir otra vez devuelve lo mismo', () {
      // Tras ajustar a 102, el área pasa a ser 63 (102 − 39) y el cálculo da 102 otra vez.
      const chrome = 39.0;
      final first = compactWindowHeight(
          outerHeight: 100, clientHeight: 100 - chrome, contentHeight: 63);
      final second = compactWindowHeight(
          outerHeight: first, clientHeight: first - chrome, contentHeight: 63);
      expect(second, first);
    });

    test('no depende de cuánta barra de título haya: el área resultante siempre es la del contenido',
        () {
      for (final chrome in [28.0, 31.0, 39.0, 47.0]) {
        final target = compactWindowHeight(
            outerHeight: 100, clientHeight: 100 - chrome, contentHeight: 63);
        expect(target - chrome, 63, reason: 'barra de $chrome px');
      }
    });

    test('nunca baja del mínimo de la ventana simple', () {
      expect(
        compactWindowHeight(outerHeight: 100, clientHeight: 90, contentHeight: 5),
        WindowLimits.compactMin.height,
      );
    });

    test('la ventana de partida deja sitio para dos líneas en un equipo normal', () {
      // La de partida (280×100) es solo un punto de salida: el ajuste la corrige.
      expect(WindowLimits.compact.height, greaterThan(WindowLimits.compactMin.height));
      expect(WindowLimits.compact.width, WindowLimits.compactMin.width);
    });
  });

  group('WindowLimits.startFor (ventana inicial = un cuarto de la pantalla)', () {
    test('ocupa la mitad de ancho y la mitad de alto', () {
      final s = WindowLimits.startFor(const Size(1920, 1080));
      expect(s, const Size(960, 540));
      expect(s.width * s.height, closeTo(1920 * 1080 / 4, 0.001));
    });

    test('en otra pantalla se adapta', () {
      expect(WindowLimits.startFor(const Size(2560, 1440)), const Size(1280, 720));
    });

    test('en una pantalla pequeña nunca baja del mínimo', () {
      expect(WindowLimits.startFor(const Size(600, 400)), WindowLimits.min);
      final s = WindowLimits.startFor(const Size(1000, 400));
      expect(s.width, 500);
      expect(s.height, WindowLimits.min.height);
    });

    test('el mínimo de la ventana no cambia', () {
      expect(WindowLimits.min, const Size(360, 242));
    });
  });
}
