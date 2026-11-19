import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gestion_time_proyect/core/services/window_service.dart';
import 'package:gestion_time_proyect/presentation/screens/dialogs/close_dialog.dart';
import 'package:gestion_time_proyect/presentation/viewModels/daily_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';

/// Intercepta el cierre de la ventana (la X) y pregunta antes de cerrar.
///
/// - Con la opción "Confirmar al cerrar" apagada y sin tickets en curso, cierra directo.
/// - Si no, muestra `showCloseDialog` (que ofrece pausar / subir a Jira / dejar corriendo
///   cuando hay tickets en curso).
/// - Si la vista simple está activa, antes de preguntar vuelve a la vista completa
///   (la ventana simple es demasiado pequeña para el diálogo y no se redimensiona).
class CloseGuard extends StatefulWidget {
  const CloseGuard({
    super.key,
    required this.controller,
    required this.daily,
    required this.window,
    required this.child,
    this.beforePrompt,
  });

  final ProjectsController controller;
  final DailyController daily;
  final WindowService window;
  final Widget child;

  /// Se ejecuta antes de mostrar la pregunta (p. ej. salir de la vista simple).
  final Future<void> Function()? beforePrompt;

  @override
  State<CloseGuard> createState() => _CloseGuardState();
}

class _CloseGuardState extends State<CloseGuard> {
  StreamSubscription<void>? _sub;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.window.closeRequests.listen((_) => _onCloseRequested());
    widget.window.setPreventClose(true);
  }

  Future<void> _onCloseRequested() async {
    // Un segundo clic en la X con la pregunta abierta no abre otra.
    if (_asking) return;
    final controller = widget.controller;
    if (!controller.confirmClose && controller.running.isEmpty) {
      await widget.window.close();
      return;
    }
    _asking = true;
    try {
      await widget.beforePrompt?.call();
      if (!mounted) return;
      final close = await showCloseDialog(
        context,
        controller: controller,
        daily: widget.daily,
      );
      if (close == true) await widget.window.close();
    } finally {
      _asking = false;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
