import 'package:flutter/material.dart';

import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/widgets/widgets.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';
import 'package:gestion_time_proyect/core/utils/duration_format.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/domain/usecases/split_minutes.dart';
import 'package:gestion_time_proyect/presentation/screens/dialogs/after_cut_dialog.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';

/// Corte: muestra el resumen de lo que se va a registrar en Jira (ticket,
/// tiempo, inicio, comentario), deja modificar el tiempo (horas y minutos, sin
/// segundos) y el comentario, y solo entonces lo envía. El cronómetro se reinicia
/// (o, si se desmarca, solo baja en lo enviado).
///
/// Si el cronómetro corría al enviar, después pregunta si se detiene o se reinicia.
Future<void> showJiraCutDialog(
  BuildContext context,
  JiraController jira,
  ProjectsController projects,
  Project project,
) async {
  final messenger = ScaffoldMessenger.of(context);
  // `true` = se envió y el cronómetro corría; `false` = se envió y estaba pausado.
  final wasRunning = await showFittedDialog<bool>(
    context: context,
    builder: (_) => _CutDialog(jira: jira, projects: projects, project: project),
  );
  if (wasRunning == null) return;
  messenger.showSnackBar(
    SnackBar(content: Text(jira.message ?? 'Tiempo registrado en Jira.')),
  );
  if (!wasRunning || !context.mounted) return;
  final current = projects.projects
      .where((p) => p.id == project.id)
      .firstOrNull;
  if (current == null || !current.isRunning) return;
  final keepRunning = await showAfterCutDialog(context, current);
  if (!keepRunning) await projects.pause(current);
}

class _CutDialog extends StatefulWidget {
  const _CutDialog({
    required this.jira,
    required this.projects,
    required this.project,
  });

  final JiraController jira;
  final ProjectsController projects;
  final Project project;

  @override
  State<_CutDialog> createState() => _CutDialogState();
}

class _CutDialogState extends State<_CutDialog> {
  final _comment = TextEditingController();
  late final TextEditingController _h;
  late final TextEditingController _m;
  bool _reset = true;

  /// Tiempo medido al abrir el diálogo, **sin segundos**: valor inicial editable. No
  /// se vuelve a leer mientras se edita.
  late final Duration _measured;

  @override
  void initState() {
    super.initState();
    _measured = Duration(
      minutes: (_current?.elapsed() ?? Duration.zero).inMinutes,
    );
    _h = TextEditingController();
    _m = TextEditingController();
    _fill(_measured);
    for (final c in [_h, _m]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_comment, _h, _m]) {
      c.dispose();
    }
    super.dispose();
  }

  Project? get _current => widget.projects.projects
      .where((p) => p.id == widget.project.id)
      .firstOrNull;

  void _fill(Duration d) {
    final hm = const SplitMinutes()(d);
    _h.text = hm.hours.toString();
    _m.text = hm.minutes.toString();
  }

  int _n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  /// Tiempo escrito en los campos.
  Duration get _entered =>
      Duration(seconds: SplitMinutes.seconds(_n(_h), _n(_m)));

  String? _problem(Duration d) {
    if (d.inSeconds < JiraController.minLogSeconds) {
      return 'Mínimo 1 minuto para registrar.';
    }
    if (d.inSeconds > JiraController.maxLogSeconds) {
      return 'Máximo 24 horas por registro.';
    }
    return null;
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// "hoy 14:32", "ayer 23:10" o "03/11 09:00".
  static String _when(DateTime t) {
    final now = DateTime.now();
    final day = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'hoy ${_clock(t)}';
    if (diff == 1) return 'ayer ${_clock(t)}';
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} ${_clock(t)}';
  }

  Future<void> _send() async {
    final wasRunning = _current?.isRunning ?? false;
    final ok = await widget.jira.logWork(
      widget.project,
      _comment.text,
      widget.projects,
      duration: _entered,
      reset: _reset,
    );
    if (!ok || !mounted) return;
    Navigator.pop(context, wasRunning);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.jira, widget.projects]),
      builder: (context, _) {
        final jira = widget.jira;
        final now = _current?.elapsed() ?? Duration.zero;
        final entered = _entered;
        final problem = _problem(entered);
        final remaining = _reset ? Duration.zero : now - entered;
        final edited = entered != _measured;

        return AlertDialog(
          title: const Text('Cortar y enviar a Jira'),
          content: AppDialogBody(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (jira.busy) const LinearProgressIndicator(),
                Text(
                  widget.project.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.md),
                // Wrap: con la ventana estrecha el botón baja a otra línea en vez
                // de desbordarse.
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Tiempo a registrar',
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (edited)
                      TextButton(
                        onPressed: jira.busy ? null : () => _fill(_measured),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                          ),
                        ),
                        child: Text(
                          'Usar el medido (${formatHoursMinutes(_measured)})',
                          style: const TextStyle(fontSize: AppFontSize.caption),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField.digits(
                        controller: _h,
                        label: 'h',
                        maxLength: FieldLimits.hoursDigits,
                        enabled: !jira.busy,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AppTextField.digits(
                        controller: _m,
                        label: 'min',
                        maxLength: FieldLimits.minutesSecondsDigits,
                        enabled: !jira.busy,
                      ),
                    ),
                  ],
                ),
                if (problem != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    problem,
                    style: TextStyle(
                      color: scheme.error,
                      fontSize: AppFontSize.label,
                    ),
                  ),
                ],
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _reset,
                  onChanged: jira.busy
                      ? null
                      : (v) => setState(() => _reset = v ?? true),
                  title: const Text('Reiniciar el cronómetro al subir'),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppTextField.multiline(
                  controller: _comment,
                  label: 'Comentario (opcional)',
                  enabled: !jira.busy,
                ),
                const SizedBox(height: AppSpacing.md),
                _summary(scheme, entered, remaining, problem == null),
                if (jira.error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    jira.error!,
                    style: TextStyle(
                      color: scheme.error,
                      fontSize: AppFontSize.label,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: jira.busy ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: jira.busy || problem != null ? null : _send,
              child: const Text('Enviar a Jira'),
            ),
          ],
        );
      },
    );
  }

  /// Qué se va a registrar y qué quedará en el cronómetro, en vivo.
  Widget _summary(
    ColorScheme scheme,
    Duration entered,
    Duration remaining,
    bool valid,
  ) {
    final started = DateTime.now().subtract(entered);
    Widget row(String k, String v, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              k,
              style: TextStyle(
                fontSize: AppFontSize.label,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontSize: AppFontSize.label,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                color: strong && valid ? scheme.primary : null,
              ),
            ),
          ),
        ],
      ),
    );

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionLabel('Resumen'),
          row(
            'Se registrará',
            valid ? formatWorkDuration(entered) : '—',
            strong: true,
          ),
          row('Inicio (aprox.)', valid ? _when(started) : '—'),
          row(
            'Quedará en el reloj',
            remaining.isNegative
                ? '00:00:00'
                : (_reset
                      ? 'En cero (se reinicia)'
                      : formatDuration(remaining)),
          ),
        ],
      ),
    );
  }
}
