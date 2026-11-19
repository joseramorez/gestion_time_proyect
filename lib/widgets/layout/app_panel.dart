import 'package:flutter/material.dart';

import 'package:gestion_time_proyect/config/theme/app_tokens.dart';

/// Aspecto de un panel.
///
///  * `filled`: fondo suave, para agrupar información (descripción, resumen,
///    seguimiento de tiempo).
///  * `outlined`: solo borde, para algo que se puede pulsar (el enlace).
enum AppPanelVariant { filled, outlined }

/// Caja con esquinas redondeadas que agrupa contenido dentro de un diálogo.
/// Ocupa todo el ancho disponible; con `onTap` se vuelve pulsable.
class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    required this.child,
    this.variant = AppPanelVariant.filled,
    this.padding = const EdgeInsets.all(AppSpacing.panel),
    this.onTap,
    this.tooltip,
  });

  final Widget child;
  final AppPanelVariant variant;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filled = variant == AppPanelVariant.filled;

    Widget panel = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: filled
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.45)
            : null,
        border: filled ? null : Border.all(color: scheme.outlineVariant),
        borderRadius: AppRadius.mdAll,
      ),
      child: child,
    );

    if (onTap != null) {
      panel = InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: onTap,
        child: panel,
      );
    }
    return tooltip == null ? panel : Tooltip(message: tooltip!, child: panel);
  }
}
