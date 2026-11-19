import 'package:flutter/material.dart';

import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/core/utils/duration_format.dart';
import 'package:gestion_time_proyect/domain/entities/day_key.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/domain/usecases/evaluate_goal.dart';
import 'package:gestion_time_proyect/domain/usecases/prepare_worklog.dart';
import 'package:gestion_time_proyect/domain/usecases/split_minutes.dart';
import 'package:gestion_time_proyect/presentation/screens/dialogs/jira_dialog.dart';
import 'package:gestion_time_proyect/presentation/viewModels/daily_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:gestion_time_proyect/widgets/widgets.dart';

/// Corte del día: lo abre el usuario cuando quiere (botón de la barra del día). Lista
/// todos los tickets con tiempo y deja subirlos a Jira **uno por uno o todos a la
/// vez**, eligiendo horas y minutos (los segundos no se tienen en cuenta). Nada se
/// impone: el total frente a la meta es solo una referencia.
Future<void> showDayCutDialog(
  BuildContext context,
  DailyController daily,
  JiraController jira,
  ProjectsController projects,
) {
  return showFittedDialog<void>(
    context: context,
    builder: (_) => _DayCutDialog(daily: daily, jira: jira, projects: projects),
  );
}

class _DayCutDialog extends StatefulWidget {
  const _DayCutDialog({
    required this.daily,
    required this.jira,
    required this.projects,
  });

  final DailyController daily;
  final JiraController jira;
  final ProjectsController projects;

  @override
  State<_DayCutDialog> createState() => _DayCutDialogState();
}

class _DayCutDialogState extends State<_DayCutDialog> {
  /// Tickets con tiempo al abrir el diálogo (en orden de la lista).
  final List<int> _ids = [];
  final Map<int, TextEditingController> _hours = {};
  final Map<int, TextEditingController> _minutes = {};

  /// Minutos ya subidos desde este diálogo (ticket → minutos).
  final Map<int, int> _done = {};
  final Map<int, String> _errors = {};
  bool _reset = true;

  /// Día trabajado elegido por ticket de Jira (`YYYY-MM-DD`). Parte del día desde el que
  /// viene el tiempo del ticket si es anterior a hoy; si no, de hoy.
  final Map<int, String> _days = {};

  /// Tickets de Jira que traían tiempo de un día anterior al abrir el diálogo.
  final List<int> _carried = [];

  @override
  void initState() {
    super.initState();
    for (final p in widget.projects.projects) {
      if (p.elapsed().inSeconds < PrepareWorklog.minSeconds) continue;
      _ids.add(p.id!);
      if (p.jiraKey == null) continue;
      _days[p.id!] = widget.daily.suggestedDay(p);
      if (p.carriesTimeBefore(widget.daily.today)) _carried.add(p.id!);
      final hm = const SplitMinutes()(p.elapsed());
      _hours[p.id!] = TextEditingController(text: hm.hours.toString());
      _minutes[p.id!] = TextEditingController(text: hm.minutes.toString());
      for (final c in [_hours[p.id!]!, _minutes[p.id!]!]) {
        c.addListener(() => setState(() {}));
      }
    }
  }

  @override
  void dispose() {
    for (final c in [..._hours.values, ..._minutes.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Project? _project(int id) =>
      widget.projects.projects.where((p) => p.id == id).firstOrNull;

  int _n(TextEditingController? c) => int.tryParse(c?.text.trim() ?? '') ?? 0;

  /// Minutos escritos para el ticket.
  int _entered(int id) => _n(_hours[id]) * 60 + _n(_minutes[id]);

  bool _valid(int minutes) =>
      minutes * 60 >= PrepareWorklog.minSeconds &&
      minutes * 60 <= PrepareWorklog.maxSeconds;

  /// Tickets de Jira todavía por subir con un tiempo válido.
  Map<int, int> get _pending => {
    for (final id in _ids)
      if (_hours.containsKey(id) &&
          !_done.containsKey(id) &&
          _valid(_entered(id)))
        id: _entered(id),
  };

  String _label(String key) {
    final today = widget.daily.today;
    if (key == today) return 'Hoy';
    final t = dayStartOf(today);
    final d = dayStartOf(key);
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${two(d.day)}/${two(d.month)}';
    return key == dayKey(DateTime(t.year, t.month, t.day - 1))
        ? 'Ayer ($date)'
        : 'Anterior ($date)';
  }

  /// Los dos escenarios: hoy y el registro anterior del ticket (el día de antes, o varios
  /// días atrás si el tiempo viene de más lejos).
  List<String> _options(int id) {
    final project = _project(id);
    final previous = project == null
        ? previousWorkday(widget.daily.today)
        : widget.daily.previousDayFor(project);
    final days = [widget.daily.today, previous];
    final chosen = _days[id];
    if (chosen != null && !days.contains(chosen)) days.add(chosen);
    return days;
  }

  Widget _dayRow(int id, bool sending) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Flexible(
          child: Text(
            'Día trabajado',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        DropdownButton<String>(
          isDense: true,
          value: _days[id],
          items: [
            for (final d in _options(id))
              DropdownMenuItem(value: d, child: Text(_label(d))),
          ],
          onChanged: sending
              ? null
              : (v) => setState(() {
                  if (v != null) _days[id] = v;
                }),
        ),
      ],
    );
  }

  Future<void> _uploadOne(int id) async {
    final project = _project(id);
    if (project == null) return;
    final error = await widget.daily.upload(
      project,
      _entered(id),
      reset: _reset,
      day: _days[id],
    );
    if (!mounted) return;
    setState(() {
      if (error == null) {
        _done[id] = _entered(id);
        _errors.remove(id);
      } else {
        _errors[id] = error;
      }
    });
  }

  Future<void> _uploadAll() async {
    final batch = _pending;
    if (batch.isEmpty) return;
    final errors = await widget.daily.uploadAll([
      for (final e in batch.entries)
        UploadRequest(e.key, e.value, _days[e.key]),
    ], reset: _reset);
    if (!mounted) return;
    setState(() {
      for (final id in batch.keys) {
        if (errors.containsKey(id)) {
          _errors[id] = errors[id]!;
        } else {
          _done[id] = batch[id]!;
          _errors.remove(id);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.daily,
        widget.jira,
        widget.projects,
      ]),
      builder: (context, _) {
        final daily = widget.daily;
        final sending = daily.sending;
        final pending = _pending;
        final hasJiraRows = _hours.isNotEmpty;
        final blockedByJira = hasJiraRows && !daily.canSend;

        return AlertDialog(
          title: const Text('Corte del día'),
          content: AppDialogBody(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (sending) const LinearProgressIndicator(),
                Text(
                  _ids.isEmpty
                      ? 'Ningún ticket tiene todavía al menos 1 minuto.'
                      : 'Sube a Jira el tiempo de cada ticket, uno por uno o todos a la vez. '
                            'Solo cuentan horas y minutos.',
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (_carried.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _carried.length == 1
                        ? 'Un ticket trae tiempo de un día anterior: elige el día en '
                              'que lo trabajaste. No se podrá iniciar hasta subirlo o limpiarlo.'
                        : '${_carried.length} tickets traen tiempo de días anteriores: '
                              'elige el día en que los trabajaste. No se podrán iniciar '
                              'hasta subirlos o limpiarlos.',
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ],
                if (_ids.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final id in _ids) _row(id, scheme, sending),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (hasJiraRows)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _reset,
                      onChanged: sending
                          ? null
                          : (v) => setState(() => _reset = v ?? true),
                      title: const Text('Reiniciar el cronómetro al subir'),
                      subtitle: const Text(
                        'Lo que sobre de los segundos se descarta. Sin marcar, se conserva.',
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  _total(pending, scheme),
                ],
                if (blockedByJira) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.jira.signedIn
                              ? 'Falta el permiso de escritura en Jira: cierra sesión e '
                                    'inicia de nuevo.'
                              : 'No has iniciado sesión en Jira, así que no se puede subir.',
                          style: const TextStyle(fontSize: AppFontSize.label),
                        ),
                        TextButton(
                          onPressed: () => showJiraDialog(
                            context,
                            widget.jira,
                            widget.projects,
                          ),
                          child: const Text('Abrir Jira'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
            if (hasJiraRows)
              FilledButton(
                onPressed: sending || blockedByJira || pending.isEmpty
                    ? null
                    : _uploadAll,
                child: Text(
                  pending.length > 1
                      ? 'Subir todos (${pending.length})'
                      : 'Subir todos',
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _row(int id, ColorScheme scheme, bool sending) {
    final project = _project(id);
    if (project == null) return const SizedBox.shrink();
    final isJira = project.jiraKey != null;
    final done = _done[id];
    final error = _errors[id];
    final sentToday = widget.daily.sentTodayByProject[id] ?? 0;
    final sub = [
      'Marca ${formatHoursMinutes(project.elapsed())}',
      if (sentToday >= 60)
        'subido hoy ${formatHoursMinutes(Duration(seconds: sentToday))}',
      if (project.carriesTimeBefore(widget.daily.today))
        'trae tiempo de ${_label(project.timeSinceDay!).toLowerCase()}',
      if (!isJira) 'manual: no se sube',
    ].join(' · ');
    final minutes = _entered(id);
    final valid = _valid(minutes);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            project.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(
            sub,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (isJira) ...[
            const SizedBox(height: AppSpacing.xs),
            if (done != null)
              Text(
                '✓ Subido ${formatHoursMinutes(Duration(minutes: done))}'
                '${_days[id] == widget.daily.today ? '' : ' · ${_label(_days[id]!)}'}',
                style: TextStyle(
                  fontSize: AppFontSize.label,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSuccess(Theme.of(context).brightness),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: AppTextField.digits(
                          controller: _hours[id]!,
                          label: 'h',
                          maxLength: FieldLimits.hoursDigits,
                          enabled: !sending,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(
                        width: 64,
                        child: AppTextField.digits(
                          controller: _minutes[id]!,
                          label: 'min',
                          maxLength: FieldLimits.minutesSecondsDigits,
                          enabled: !sending,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: sending || !widget.daily.canSend || !valid
                            ? null
                            : () => _uploadOne(id),
                        child: const Text('Subir'),
                      ),
                    ],
                  ),
                  _dayRow(id, sending),
                ],
              ),
          ],
          if (error != null)
            Text(
              error,
              style: TextStyle(
                color: scheme.error,
                fontSize: AppFontSize.caption,
              ),
            ),
        ],
      ),
    );
  }

  /// "Reportado X / meta" (lo subido hoy + lo que se va a subir) y cómo queda frente a
  /// la meta y al mínimo.
  Widget _total(Map<int, int> pending, ColorScheme scheme) {
    final daily = widget.daily;
    final today = daily.today;
    int sum(Iterable<MapEntry<int, int>> e) => e.fold(0, (a, b) => a + b.value);
    final toUpload = Duration(
      minutes: sum(pending.entries.where((e) => _days[e.key] == today)),
    );
    final forOtherDays = Duration(
      minutes: sum(pending.entries.where((e) => _days[e.key] != today)),
    );
    final reported = daily.sentToday + toUpload;
    const eval = EvaluateGoal();
    final status = eval(
      total: reported,
      goal: daily.goal,
      minimum: daily.minimum,
    );
    final diff = formatHoursMinutes(
      eval.difference(total: reported, goal: daily.goal),
    );
    final (label, tone) = switch (status) {
      GoalStatus.short => (
        'Faltan $diff (mínimo ${formatHoursMinutes(daily.minimum)})',
        AppChipTone.danger,
      ),
      GoalStatus.acceptable => ('Aceptable · faltan $diff', AppChipTone.accent),
      GoalStatus.met => ('Día completo', AppChipTone.success),
      GoalStatus.over => ('Sobran $diff', AppChipTone.success),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Reportado ${formatHoursMinutes(reported)} / ${formatHoursMinutes(daily.goal)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            AppChip(label: label, tone: tone),
          ],
        ),
        Text(
          'Subido hoy ${formatHoursMinutes(daily.sentToday)} · por subir hoy ${formatHoursMinutes(toUpload)}'
          '${forOtherDays.inMinutes > 0 ? ' · para otros días ${formatHoursMinutes(forOtherDays)}' : ''}',
          style: TextStyle(
            fontSize: AppFontSize.caption,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
