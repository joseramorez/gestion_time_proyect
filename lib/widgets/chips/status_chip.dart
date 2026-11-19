import 'package:flutter/material.dart';

import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/widgets/widgets.dart';

/// Estado de un ticket de Jira ("Por hacer", "En curso", "Listo"…). Es una
/// `AppChip`; lo único propio de Jira es traducir la **categoría** del estado al
/// color: `new` (por hacer) → neutro, `indeterminate` (en curso) → acento y
/// `done` (terminado) → verde. Los nombres de estado son libres en cada proyecto;
/// la categoría es lo que permite colorearlos siempre igual.
class JiraStatusChip extends StatelessWidget {
  const JiraStatusChip({
    super.key,
    required this.status,
    this.category,
    this.tooltip,
    this.pending = false,
    this.maxWidth = ChipLimits.maxWidth,
    this.onTap,
  });

  final String status;
  final String? category;

  /// Texto al pasar el cursor; por defecto "Estado en Jira: …".
  final String? tooltip;

  /// "Aún sin estado": el ticket es de Jira pero no se ha sincronizado.
  final bool pending;

  /// Ancho máximo (el hueco que le da la vista donde se use).
  final double maxWidth;

  /// Si se da, la etiqueta es pulsable (cambiar el estado) y el tooltip lo indica.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final base = tooltip ?? 'Estado en Jira: $status';
    final chip = AppChip(
      label: status,
      tone: switch (category) {
        'done' => AppChipTone.success,
        'indeterminate' => AppChipTone.accent,
        _ => AppChipTone.neutral,
      },
      tooltip: onTap == null ? base : '$base · clic para cambiar',
      muted: pending,
      maxWidth: maxWidth,
    );
    if (onTap == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: chip,
    );
  }
}
