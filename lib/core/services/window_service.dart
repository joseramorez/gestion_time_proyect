import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:window_manager/window_manager.dart';

import 'package:gestion_time_proyect/config/theme/theme.dart';

/// Alto exacto que debe tener la ventana simple para que el contenido quepa.
///
/// `outerHeight` es el alto de la ventana y `clientHeight` el del área donde Flutter
/// dibuja; su diferencia es lo que ocupan la barra de título y los bordes en este
/// equipo (con otra escala de pantalla, otra cifra). Se le suma el alto del
/// contenido (`contentHeight`) y nunca baja de `WindowLimits.compactMin`.
double compactWindowHeight({
  required double outerHeight,
  required double clientHeight,
  required double contentHeight,
}) {
  final chrome = outerHeight - clientHeight;
  return math.max(contentHeight + chrome, WindowLimits.compactMin.height);
}

/// Operaciones sobre la ventana nativa que necesita la interfaz. Existe como
/// interfaz para que las pruebas usen un doble y no dependan del plugin de
/// escritorio (que no está disponible en `flutter test`).
abstract interface class WindowService {
  Future<void> setAlwaysOnTop(bool value);
  Future<void> setOpacity(double value);

  /// Pasa a la vista simple: ventana compacta, siempre encima, sin redimensionar
  /// y con la transparencia propia de esa vista.
  Future<void> enterCompact({required double opacity});

  /// Ajusta el alto de la ventana simple al contenido. `content` es el tamaño
  /// óptimo del contenido y `client` el tamaño actual del área de la vista (ambos
  /// en píxeles lógicos). La diferencia entre el tamaño de la ventana y `client`
  /// es lo que ocupan la barra de título y los bordes *en este equipo*; se suma al
  /// contenido para obtener el alto exacto de la ventana.
  Future<void> fitCompact({required Size content, required Size client});

  /// Vuelve a la vista completa: recupera el tamaño que tenía antes (nunca menor
  /// que el mínimo), el "siempre encima" elegido para esa vista y su transparencia.
  Future<void> exitCompact({
    required double opacity,
    required bool alwaysOnTop,
  });

  /// Cada vez que el usuario intenta cerrar la ventana (la X) y el cierre está
  /// retenido (`setPreventClose(true)`): la app decide si de verdad se cierra.
  Stream<void> get closeRequests;

  /// Con `true`, la X de la ventana no la cierra: avisa por `closeRequests`.
  Future<void> setPreventClose(bool value);

  /// Cierra la ventana y termina la app, sin volver a preguntar.
  Future<void> close();
}

/// Implementación real con `window_manager`.
class ManagedWindowService with WindowListener implements WindowService {
  ManagedWindowService() {
    windowManager.addListener(this);
  }

  final _closeRequests = StreamController<void>.broadcast();

  @override
  Stream<void> get closeRequests => _closeRequests.stream;

  @override
  void onWindowClose() => _closeRequests.add(null);

  @override
  Future<void> setPreventClose(bool value) =>
      windowManager.setPreventClose(value);

  @override
  Future<void> close() => windowManager.destroy();

  /// Tamaño de la vista completa, guardado al entrar en la vista simple.
  Size? _previousSize;

  /// Ejecuta un paso sobre la ventana nativa sin que su fallo impida los siguientes.
  /// Sobre todo al volver a la vista completa: si, por ejemplo, no se pudo cambiar
  /// el tamaño, aun así hay que recuperar la transparencia y la superposición, y
  /// sobre todo no dejar la ventana sin redimensionar.
  Future<void> _step(String name, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('Ventana: falló "$name": $e');
    }
  }

  @override
  Future<void> setAlwaysOnTop(bool value) =>
      windowManager.setAlwaysOnTop(value);

  @override
  Future<void> setOpacity(double value) => windowManager.setOpacity(value);

  @override
  Future<void> enterCompact({required double opacity}) async {
    // `??=`: si se entra dos veces seguidas no se pisa el tamaño de la vista completa.
    await _step('guardar el tamaño', () async {
      _previousSize ??= await windowManager.getSize();
    });
    // El mínimo se baja primero: si no, la ventana no puede encogerse.
    await _step(
      'mínimo',
      () => windowManager.setMinimumSize(WindowLimits.compactMin),
    );
    await _step('tamaño', () => windowManager.setSize(WindowLimits.compact));
    await _step('no redimensionable', () => windowManager.setResizable(false));
    await _step('siempre encima', () => windowManager.setAlwaysOnTop(true));
    await _step('transparencia', () => windowManager.setOpacity(opacity));
  }

  @override
  Future<void> fitCompact({required Size content, required Size client}) async {
    final outer = await windowManager.getSize();
    final target = compactWindowHeight(
      outerHeight: outer.height,
      clientHeight: client.height,
      contentHeight: content.height,
    );
    // Ya mide lo que debe: no se toca (así el ajuste converge y no parpadea).
    if ((target - outer.height).abs() < 1) return;
    await windowManager.setSize(Size(outer.width, target));
  }

  @override
  Future<void> exitCompact({
    required double opacity,
    required bool alwaysOnTop,
  }) async {
    await _step('redimensionable', () => windowManager.setResizable(true));
    await _step('mínimo', () => windowManager.setMinimumSize(WindowLimits.min));
    final previous = _previousSize ?? WindowLimits.min;
    _previousSize = null;
    await _step(
      'tamaño',
      () => windowManager.setSize(
        Size(
          math.max(previous.width, WindowLimits.min.width),
          math.max(previous.height, WindowLimits.min.height),
        ),
      ),
    );
    await _step(
      'siempre encima',
      () => windowManager.setAlwaysOnTop(alwaysOnTop),
    );
    await _step('transparencia', () => windowManager.setOpacity(opacity));
  }
}
