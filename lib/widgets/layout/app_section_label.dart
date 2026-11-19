import 'package:flutter/material.dart';

import 'package:gestion_time_proyect/config/theme/app_tokens.dart';

/// Rótulo de sección en mayúsculas ("DESCRIPCIÓN", "ENLACE", "RESUMEN"…). El
/// texto se pasa en minúsculas normales; el componente lo pone en mayúsculas,
/// así todos los rótulos se escriben y se ven igual.
class AppSectionLabel extends StatelessWidget {
  const AppSectionLabel(this.text, {super.key, this.bottomGap = AppSpacing.xs});

  final String text;

  /// Separación bajo el rótulo (0 si va dentro de un panel con su propio ritmo).
  final double bottomGap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: AppFontSize.micro,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
