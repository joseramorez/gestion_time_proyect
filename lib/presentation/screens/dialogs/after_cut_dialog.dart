import 'package:flutter/material.dart';
import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/widgets/widgets.dart';

/// Después de enviar el tiempo de un ticket cuyo cronómetro **seguía corriendo**: pregunta
/// si se detiene o si se reinicia (sigue corriendo desde cero). Devuelve `true` para seguir
/// corriendo; `false` para detenerlo. No se puede cerrar sin elegir.
Future<bool> showAfterCutDialog(BuildContext context, Project project) async {
  final keepRunning = await showFittedDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Tiempo enviado'),
      content: AppDialogBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              project.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('El cronómetro sigue corriendo. ¿Lo detienes o lo reinicias?'),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Detener'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Reiniciar'),
        ),
      ],
    ),
  );
  return keepRunning ?? true;
}
