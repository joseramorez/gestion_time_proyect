import 'package:flutter/material.dart';

/// Colores que no salen del `ColorScheme` de Material. Los que sí salen (primario,
/// error, superficies…) se leen del tema; aquí solo va lo propio de la app.
abstract final class AppColors {
  /// Verde de "éxito" / ticket terminado. Un solo verde en claro y otro en
  /// oscuro, para que el texto mantenga el contraste sobre el fondo teñido.
  static const Color _success = Color(0xFF2E9E5B);
  static const Color _successOnDark = Color(0xFF8BEBB2);
  static const Color _successOnLight = Color(0xFF14602F);

  /// Color de relleno (se usa con transparencia).
  static Color success() => _success;

  /// Color del texto/icono sobre un fondo teñido de éxito.
  static Color onSuccess(Brightness brightness) =>
      brightness == Brightness.dark ? _successOnDark : _successOnLight;
}
