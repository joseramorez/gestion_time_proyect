import 'package:flutter/material.dart';

import 'package:gestion_time_proyect/config/theme/app_colors.dart';
import 'package:gestion_time_proyect/config/theme/app_limits.dart';
import 'package:gestion_time_proyect/config/theme/app_tokens.dart';

/// Color de una etiqueta según lo que expresa.
enum AppChipTone {
  /// Sin carga semántica (p. ej. "Por hacer").
  neutral,

  /// En marcha / destacado (color principal).
  accent,

  /// Correcto o terminado (verde).
  success,

  /// Problema o aviso (rojo).
  danger,

  /// Identidad, como la clave del ticket de Jira (contenedor del color principal).
  brand,
}

/// Forma de la etiqueta.
///
///  * `badge`: etiqueta con borde, para un **estado** (más protagonista).
///  * `soft`: píldora plana, con icono opcional, para **datos** (tiempos, clave).
enum AppChipVariant { badge, soft }

/// Etiqueta de la app: la única forma de mostrar un estado o un dato corto.
///
/// Límites: una sola línea y un ancho máximo (`maxWidth`, nunca más que
/// `ChipLimits.maxWidth`); si el texto no cabe se recorta con "…" y el
/// `tooltip` (por defecto, el propio texto) lo muestra completo. En una fila,
/// ponla dentro de un hueco con ancho acotado (`Expanded`, `Flexible`…): la
/// etiqueta se adapta a ese hueco.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.tone = AppChipTone.neutral,
    this.variant = AppChipVariant.badge,
    this.icon,
    this.tooltip,
    this.maxWidth = ChipLimits.maxWidth,
    this.muted = false,
  });

  final String label;
  final AppChipTone tone;
  final AppChipVariant variant;

  /// Icono a la izquierda (solo con `variant: soft`).
  final IconData? icon;

  /// Texto al pasar el cursor. Por defecto, `label`.
  final String? tooltip;
  final double maxWidth;

  /// Atenuada: sin relleno, borde tenue y cursiva. Para "aún sin dato".
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    final (Color bg, Color fg) = switch (tone) {
      AppChipTone.success => (
        AppColors.success().withValues(alpha: 0.28),
        AppColors.onSuccess(brightness),
      ),
      AppChipTone.accent => (
        scheme.primary.withValues(alpha: 0.26),
        scheme.primary,
      ),
      AppChipTone.danger => (
        scheme.error.withValues(alpha: 0.22),
        scheme.error,
      ),
      AppChipTone.brand => (scheme.primaryContainer, scheme.onPrimaryContainer),
      AppChipTone.neutral => (
        scheme.onSurface.withValues(alpha: 0.14),
        scheme.onSurface,
      ),
    };

    final color = muted ? scheme.onSurfaceVariant : fg;
    final isBadge = variant == AppChipVariant.badge;

    final text = Text(
      label,
      maxLines: ChipLimits.maxLines,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: TextStyle(
        fontSize: AppFontSize.label,
        fontWeight: isBadge ? FontWeight.w700 : FontWeight.w600,
        fontStyle: muted ? FontStyle.italic : FontStyle.normal,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color,
      ),
    );

    final content = Container(
      constraints: BoxConstraints(
        maxWidth: maxWidth.clamp(0.0, ChipLimits.maxWidth).toDouble(),
      ),
      padding: isBadge
          ? const EdgeInsets.symmetric(horizontal: 9, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: muted ? Colors.transparent : bg,
        borderRadius: BorderRadius.circular(isBadge ? 9 : AppRadius.sm + 2),
        border: isBadge
            ? Border.all(color: color.withValues(alpha: muted ? 0.35 : 0.45))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null && !isBadge) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Flexible(child: text),
        ],
      ),
    );

    return Tooltip(message: tooltip ?? label, child: content);
  }
}
