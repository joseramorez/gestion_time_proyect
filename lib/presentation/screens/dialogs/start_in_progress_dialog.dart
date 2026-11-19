import 'package:flutter/material.dart';
import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/widgets/widgets.dart';

/// Qué hacer al iniciar el cronómetro de un ticket que aún no está en curso en Jira.
enum StartChoice { cancel, startOnly, startInProgress }

/// Pregunta si, además de iniciar el cronómetro, se pasa el ticket a «en curso».
/// Cerrar el diálogo sin elegir equivale a cancelar: no se inicia nada.
Future<StartChoice> showStartInProgressDialog(
  BuildContext context,
  Project project,
) async {
  final choice = await showFittedDialog<StartChoice>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Poner el ticket en curso?'),
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
            Row(
              children: [
                Text(
                  'Estado en Jira: ',
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                JiraStatusChip(
                  status: project.jiraStatus ?? '',
                  category: project.jiraStatusCategory,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, StartChoice.cancel),
          child: const Text('Cancelar'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, StartChoice.startOnly),
          child: const Text('Solo iniciar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, StartChoice.startInProgress),
          child: const Text('Poner en curso'),
        ),
      ],
    ),
  );
  return choice ?? StartChoice.cancel;
}
