import 'package:flutter/widgets.dart';

/// Tokens de diseño: las medidas "sueltas" de toda la app. Ninguna pantalla
/// debería escribir `EdgeInsets.all(12)` o `BorderRadius.circular(16)` a mano:
/// se usa el token, y cambiar el aspecto de la app es cambiar un número aquí.

/// Espacios (márgenes, relleno y separaciones), en píxeles lógicos.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  /// Relleno interno de un panel (`AppPanel`).
  static const double panel = 10;
}

/// Radios de esquina.
abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
}

/// Tamaños de letra.
abstract final class AppFontSize {
  /// Rótulos de sección en mayúsculas.
  static const double micro = 10;

  /// Texto secundario (p. ej. "En Jira: 1 h 05 m").
  static const double caption = 11;

  /// Etiquetas y chips.
  static const double label = 12;

  /// Texto de cuerpo y nombre en la tarjeta.
  static const double body = 13;

  /// Título de detalle.
  static const double title = 16;

  /// Título de la barra superior.
  static const double appBar = 17;

  /// Título de diálogo.
  static const double dialogTitle = 18;

  /// Cronómetro de la tarjeta.
  static const double timer = 20;

  /// Cronómetro de la vista simple (un poco mayor: es lo único que se muestra).
  static const double compactTimer = 24;
}

/// Duraciones de animación.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 220);
}

/// Tamaños del botón de icono. `box` es el lado del botón y `icon` el del icono.
///
/// Dónde va cada uno:
///  * `compact`: acciones secundarias dentro de una tarjeta (limpiar, cortar,
///    información). Es lo que permite que quepa la etiqueta de estado.
///  * `regular`: barra superior y acciones de diálogos.
///  * `large`: la acción principal de una fila (play/pausa).
enum AppIconButtonSize {
  compact(box: 30, icon: 18),
  regular(box: 36, icon: 20),
  large(box: 40, icon: 24);

  const AppIconButtonSize({required this.box, required this.icon});

  final double box;
  final double icon;
}
