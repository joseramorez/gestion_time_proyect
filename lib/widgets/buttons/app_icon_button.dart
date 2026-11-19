import 'package:flutter/material.dart';
import 'package:gestion_time_proyect/config/theme/app_tokens.dart';

/// Aspecto del botón: `plain` (solo icono), `tonal` (fondo suave) o `filled`
/// (fondo de color principal, para la acción más importante de la vista).
enum AppIconButtonVariant { plain, tonal, filled }

/// Botón de icono de la app. Es la única forma de poner un botón de icono: fija
/// tamaños y colores, **exige `tooltip`** (accesibilidad y claridad: un icono
/// solo no dice qué hace) y evita un fallo conocido de Flutter: dentro de una
/// `AppBar`, esta impone su propio color de iconos y pisa el de los botones
/// rellenos; aquí los colores de `tonal` y `filled` se fijan explícitamente.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.variant = AppIconButtonVariant.plain,
    this.size = AppIconButtonSize.regular,
    this.selected = false,
    this.selectedIcon,
    this.color,
  });

  final IconData icon;
  final String tooltip;

  /// `null` deshabilita el botón.
  final VoidCallback? onPressed;
  final AppIconButtonVariant variant;
  final AppIconButtonSize size;

  /// Estado "activado" (p. ej. el pin de superposición): usa `selectedIcon`.
  final bool selected;
  final IconData? selectedIcon;

  /// Color del icono en `plain` (p. ej. el rojo de "Eliminar"). Se ignora en
  /// `tonal` y `filled`, que tienen colores propios.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (Color? bg, Color? fg) = switch (variant) {
      AppIconButtonVariant.filled => (scheme.primary, scheme.onPrimary),
      AppIconButtonVariant.tonal => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      AppIconButtonVariant.plain => (null, color),
    };

    final style = IconButton.styleFrom(
      fixedSize: Size.square(size.box),
      minimumSize: Size.square(size.box),
      padding: EdgeInsets.zero,
      iconSize: size.icon,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      backgroundColor: bg,
      foregroundColor: fg,
    );

    final child = Icon(icon);
    final chosen = selectedIcon == null ? null : Icon(selectedIcon);

    return switch (variant) {
      AppIconButtonVariant.plain => IconButton(
        tooltip: tooltip,
        style: style,
        isSelected: selected,
        selectedIcon: chosen,
        icon: child,
        onPressed: onPressed,
      ),
      _ => IconButton.filled(
        tooltip: tooltip,
        style: style,
        isSelected: selected,
        selectedIcon: chosen,
        icon: child,
        onPressed: onPressed,
      ),
    };
  }
}
