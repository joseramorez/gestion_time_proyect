import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/widgets/widgets.dart';
import 'package:gestion_time_proyect/core/utils/duration_format.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:gestion_time_proyect/presentation/screens/dialogs/jira_status_menu.dart';
import 'package:gestion_time_proyect/presentation/screens/dialogs/project_form_dialog.dart';

/// Detalle de un proyecto/ticket: descripción, enlace y tiempos, con acciones
/// de editar y eliminar.
///
/// A diferencia de otros diálogos NO agranda la ventana: nunca pasa del alto
/// que ya tiene. Si la descripción no cabe, se trunca con "…" y "Ver más" la
/// abre en una zona con scroll de ese mismo alto máximo.
Future<void> showProjectInfo(
  BuildContext context,
  ProjectsController controller,
  Project project, {
  JiraController? jira,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _InfoDialog(
      jira: jira,
      controller: controller,
      project: project,
      parentContext: context,
    ),
  );
}

class _InfoDialog extends StatefulWidget {
  const _InfoDialog({
    required this.controller,
    required this.project,
    required this.parentContext,
    this.jira,
  });

  /// Si se da, el estado de Jira se puede cambiar desde aquí.
  final JiraController? jira;
  final ProjectsController controller;
  final Project project;
  final BuildContext parentContext;

  @override
  State<_InfoDialog> createState() => _InfoDialogState();
}

class _InfoDialogState extends State<_InfoDialog> {
  bool _expanded = false;

  static const _descStyle = TextStyle(fontSize: AppFontSize.body, height: 1.4);
  static const _lineHeight = AppFontSize.body * 1.4;
  static const _boxPadding = AppSpacing.panel;

  /// ¿`text` necesita más de `maxLines` líneas con el ancho dado?
  static bool _exceeds(String text, int maxLines, double width) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _descStyle),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
    )..layout(maxWidth: width);
    final exceeded = painter.didExceedMaxLines;
    painter.dispose();
    return exceeded;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = widget.controller;
    final first = widget.project;

    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: DialogLimits.infoMaxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, AppSpacing.lg, 18, 10),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              // Datos al día (el cronómetro puede estar corriendo).
              final p =
                  controller.projects
                      .where((x) => x.id == first.id)
                      .firstOrNull ??
                  first;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Solo los botones son fijos. Encabezado, tiempos y cuerpo
                  // comparten el resto del alto y, si no caben, hacen scroll
                  // en vez de desbordarse ni agrandar la ventana.
                  Flexible(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        // Ventana baja: nombre en una línea y sin etiquetas, para
                        // dejar sitio a la descripción.
                        final compact =
                            c.hasBoundedHeight &&
                            c.maxHeight < DialogLimits.infoCompactBelow;
                        return SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _header(p, compact),
                              const SizedBox(height: AppSpacing.sm),
                              // Ventana baja: la descripción va justo tras el nombre
                              // y los tiempos quedan al final (se alcanzan con scroll).
                              if (compact) ...[
                                _body(p, scheme, c, compact),
                                const SizedBox(height: 10),
                                _meta(p),
                                if (p.hasJiraTracking) ...[
                                  const SizedBox(height: 10),
                                  _tracking(p, scheme),
                                ],
                              ] else ...[
                                _meta(p),
                                if (p.hasJiraTracking) ...[
                                  const SizedBox(height: 10),
                                  _tracking(p, scheme),
                                ],
                                const SizedBox(height: 10),
                                _body(p, scheme, c, compact),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _actions(context, p, scheme),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(Project p, bool compact) {
    return Text(
      p.name,
      maxLines: compact ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: AppFontSize.title,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
    );
  }

  /// Etiquetas con la clave, el estado y los tiempos del ticket.
  Widget _meta(Project p) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (p.jiraKey != null)
          AppChip(
            label: 'Jira · ${p.jiraKey}',
            tone: AppChipTone.brand,
            variant: AppChipVariant.soft,
            icon: AppIcons.jiraTicket,
          ),
        if (p.jiraStatus != null)
          Builder(
            builder: (chipContext) => JiraStatusChip(
              status: p.jiraStatus!,
              category: p.jiraStatusCategory,
              onTap: widget.jira == null || p.jiraKey == null
                  ? null
                  : () => showJiraStatusMenu(
                      chipContext,
                      widget.jira!,
                      widget.controller,
                      p,
                    ),
            ),
          ),
        AppChip(
          label: formatDuration(p.elapsed()),
          tone: p.isRunning ? AppChipTone.accent : AppChipTone.neutral,
          variant: AppChipVariant.soft,
          icon: AppIcons.timer,
        ),
        if (p.jiraLoggedMs > 0)
          AppChip(
            label:
                'En Jira: ${formatWorkDuration(Duration(milliseconds: p.jiraLoggedMs))}',
            variant: AppChipVariant.soft,
            icon: AppIcons.sentToJira,
          ),
      ],
    );
  }

  /// "Seguimiento de tiempo" de Jira: estimado, registrado (todos los usuarios) y
  /// restante, con una barra de progreso. Jira no informa lo que no esté
  /// configurado: un valor ausente se muestra como "—", no como 0.
  Widget _tracking(Project p, ColorScheme scheme) {
    final est = p.jiraEstimateSeconds;
    final rem = p.jiraRemainingSeconds;
    final spent = p.jiraSpentSeconds;
    String fmt(int? sec) =>
        sec == null ? '—' : formatWorkDuration(Duration(seconds: sec));

    // Barra: registrado frente a la estimación; sin estimación, frente a
    // registrado + restante (como el gráfico de Jira).
    final base = est ?? ((spent ?? 0) + (rem ?? 0));
    final progress = (spent != null && base > 0)
        ? (spent / base).clamp(0.0, 1.0)
        : null;
    final over = est != null && spent != null && spent > est;

    Widget cell(String label, String value, {String? tip, Color? color}) =>
        Expanded(
          child: Tooltip(
            message: tip ?? label,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        );

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionLabel('Seguimiento de tiempo · Jira', bottomGap: 0),
          if (progress != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                color: over ? scheme.error : scheme.primary,
                backgroundColor: scheme.onSurface.withValues(alpha: 0.12),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cell('Estimado', fmt(est), tip: 'Estimación original'),
              cell(
                'Registrado',
                fmt(spent),
                tip: 'Suma de los registros de todos los usuarios en Jira',
                color: over ? scheme.error : null,
              ),
              cell('Restante', fmt(rem), tip: 'Tiempo restante estimado'),
            ],
          ),
          if (over)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Se pasó de la estimación.',
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  color: scheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(Project p, ColorScheme scheme, BoxConstraints c, bool compact) {
    final text = p.description.trim();
    final uri = Uri.tryParse(p.link);
    final canOpen =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

    // Alto que queda para la descripción tras reservar el resto del cuerpo
    // (etiquetas, enlace y botón "Ver más"), sin pasar del alto disponible.
    final reserved = compact
        ? 22 /*nombre*/ + 8 + 34 /*ver más*/
        : 44 /*nombre*/ +
              8 +
              32 /*chip y tiempos*/ +
              10 +
              22 /*etiqueta*/ +
              34 /*ver más*/ +
              (p.hasJiraTracking ? 112 : 0) /*seguimiento de tiempo*/ +
              (p.link.isEmpty ? 0 : 76) /*enlace*/;
    final available = c.hasBoundedHeight ? c.maxHeight : 400.0;
    final boxMax = (available - reserved).clamp(
      _lineHeight + 2 * _boxPadding,
      1000.0,
    );
    final maxLines = ((boxMax - 2 * _boxPadding) / _lineHeight).floor().clamp(
      1,
      1000,
    );
    final textWidth = c.maxWidth - 2 * _boxPadding;
    final overflows = text.isNotEmpty && _exceeds(text, maxLines, textWidth);

    Widget description;
    if (text.isEmpty) {
      description = Text(
        'Sin descripción',
        style: _descStyle.copyWith(
          fontStyle: FontStyle.italic,
          color: scheme.onSurfaceVariant,
        ),
      );
    } else if (_expanded && overflows) {
      description = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: boxMax - 2 * _boxPadding),
        child: Scrollbar(
          child: SingleChildScrollView(
            child: SelectableText(text, style: _descStyle),
          ),
        ),
      );
    } else {
      description = Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: _descStyle,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) const AppSectionLabel('Descripción'),
        AppPanel(child: description),
        if (overflows)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? 'Ver menos' : 'Ver más'),
            ),
          ),
        if (p.link.isNotEmpty) ...[
          const SizedBox(height: 10),
          if (!compact) const AppSectionLabel('Enlace'),
          AppPanel(
            variant: AppPanelVariant.outlined,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.panel,
              vertical: 9,
            ),
            tooltip: p.link,
            onTap: canOpen ? () => launchUrl(uri) : null,
            child: Row(
              children: [
                Icon(
                  AppIcons.link,
                  size: 16,
                  color: canOpen ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    p.link,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.label,
                      color: canOpen ? scheme.primary : null,
                    ),
                  ),
                ),
                if (canOpen)
                  Icon(AppIcons.openExternal, size: 15, color: scheme.primary),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _actions(BuildContext context, Project p, ColorScheme scheme) {
    return Row(
      children: [
        AppIconButton(
          icon: AppIcons.delete,
          tooltip: 'Eliminar',
          color: scheme.error,
          onPressed: () => _confirmDelete(context, p),
        ),
        AppIconButton(
          icon: AppIcons.edit,
          tooltip: 'Editar',
          onPressed: () {
            Navigator.pop(context);
            showProjectForm(
              widget.parentContext,
              widget.controller,
              existing: p,
            );
          },
        ),
        const Spacer(),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, Project p) async {
    final confirm = await showFittedDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Eliminar?'),
        content: Text('Se borrará "${p.name}" y su tiempo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.controller.remove(p);
      if (context.mounted) Navigator.pop(context);
    }
  }
}
