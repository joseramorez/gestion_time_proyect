import 'package:flutter/material.dart';

import 'package:gestion_time_proyect/config/theme/app_limits.dart';

/// Contenido de un diálogo con el ancho estándar (`DialogLimits`) y scroll
/// vertical. El scroll evita desbordes si el contenido es más alto que la
/// ventana; con `showFittedDialog` la ventana además se agranda para que
/// normalmente no haga falta desplazarse.
///
/// Anchos: `DialogLimits.formWidth` (por defecto: formularios, Jira, corte) y
/// `DialogLimits.compactWidth` (diálogos pequeños, como la transparencia).
class AppDialogBody extends StatelessWidget {
  const AppDialogBody({
    super.key,
    required this.child,
    this.width = DialogLimits.formWidth,
  });

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: SingleChildScrollView(child: child),
    );
  }
}
