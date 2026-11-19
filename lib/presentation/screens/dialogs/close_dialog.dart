import 'package:flutter/material.dart';
import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/core/utils/duration_format.dart';
import 'package:gestion_time_proyect/presentation/viewModels/daily_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:gestion_time_proyect/widgets/widgets.dart';

/// Pregunta antes de cerrar la app. Devuelve `true` si hay que cerrar y `false` (o
/// `null`) si el usuario cancela.
///
/// Sin tickets en curso es una simple confirmación. Con alguno, ofrece pausarlos,
/// subir su tiempo a Jira o dejarlos corriendo (el tiempo se deriva de la hora de inicio,
/// así que sobrevive al cierre).
Future<bool?> showCloseDialog(
  BuildContext context, {
  required ProjectsController controller,
  required DailyController daily,
}) {
  return showFittedDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CloseDialog(controller: controller, daily: daily),
  );
}

class _CloseDialog extends StatefulWidget {
  const _CloseDialog({required this.controller, required this.daily});

  final ProjectsController controller;
  final DailyController daily;

  @override
  State<_CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends State<_CloseDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _pause() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      for (final p in widget.controller.running) {
        await widget.controller.pause(p);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'No se pudo pausar: $e';
        });
      }
    }
  }

  Future<void> _upload() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final errors = await widget.daily.pauseAndUploadRunning();
      if (!mounted) return;
      if (errors.isEmpty) {
        Navigator.pop(context, true);
        return;
      }
      // Lo que falló quedó pausado con su tiempo intacto: se avisa y se deja decidir.
      final names = {
        for (final p in widget.controller.projects) p.id: p.name,
      };
      setState(() {
        _busy = false;
        _error = [
          'No se subió todo; revisa Jira antes de cerrar:',
          for (final e in errors.entries) '${names[e.key] ?? 'Ticket'}: ${e.value}',
        ].join('\n');
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'No se pudo subir: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, widget.daily]),
      builder: (context, _) {
        final running = widget.controller.running;
        final canUpload =
            widget.daily.canSend && widget.daily.uploadableRunning.isNotEmpty;
        final now = DateTime.now();
        return AlertDialog(
          title: const Text('¿Cerrar la aplicación?'),
          content: AppDialogBody(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (running.isEmpty)
                  const Text('No hay tiempos corriendo.')
                else ...[
                  Text(
                    running.length == 1
                        ? 'Tienes un ticket en curso:'
                        : 'Tienes ${running.length} tickets en curso:',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final p in running)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '• ${p.name} · ${formatDuration(p.elapsed(now))}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    canUpload
                        ? '¿Qué hacemos con ellos?'
                        : widget.daily.canSend
                        ? 'No hay tiempo para subir (mínimo 1 min en un ticket de Jira).'
                        : 'Para subir a Jira inicia sesión con permiso de escritura.',
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            if (running.isEmpty)
              FilledButton(
                onPressed: _busy ? null : () => Navigator.pop(context, true),
                child: const Text('Cerrar'),
              )
            else ...[
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, true),
                child: const Text('Dejar corriendo'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _pause,
                child: const Text('Pausar y cerrar'),
              ),
              FilledButton(
                onPressed: _busy || !canUpload ? null : _upload,
                child: Text(_busy ? 'Subiendo…' : 'Subir a Jira y cerrar'),
              ),
            ],
          ],
        );
      },
    );
  }
}
