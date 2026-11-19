import 'package:flutter/material.dart';
import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/domain/entities/project_filter.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:gestion_time_proyect/widgets/widgets.dart';

/// Filtros de la lista: estados, origen, actividad y atajos (el orden se elige en el menú de
/// la barra). Los cambios se aplican en vivo: no hay botón de aplicar.
Future<void> showListFilterDialog(
  BuildContext context,
  ProjectsController controller,
) {
  return showFittedDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Filtros'),
      content: ListenableBuilder(
        listenable: controller,
        builder: (_, _) => AppDialogBody(child: _Body(controller: controller)),
      ),
      actions: [
        TextButton(
          onPressed: controller.filter.isActive ? controller.clearFilter : null,
          child: const Text('Limpiar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.controller});

  final ProjectsController controller;

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
    child: Text(
      text,
      style: TextStyle(
        fontSize: AppFontSize.label,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final f = controller.filter;
    void set(ProjectFilter next) => controller.setFilter(next);
    final options = controller.statusOptions;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(context, 'Estado'),
        if (options.isEmpty)
          const Text('Aún no hay estados que filtrar.')
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final o in options)
                FilterChip(
                  label: Text(o.status),
                  selected: f.statuses.contains(o.status),
                  visualDensity: VisualDensity.compact,
                  onSelected: (on) => set(
                    f.copyWith(
                      statuses: on
                          ? {...f.statuses, o.status}
                          : ({...f.statuses}..remove(o.status)),
                    ),
                  ),
                ),
            ],
          ),
        _label(context, 'Origen'),
        SegmentedButton<ProjectOrigin>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: ProjectOrigin.all, label: Text('Todos')),
            ButtonSegment(value: ProjectOrigin.jira, label: Text('Jira')),
            ButtonSegment(value: ProjectOrigin.manual, label: Text('Manuales')),
          ],
          selected: {f.origin},
          onSelectionChanged: (s) => set(f.copyWith(origin: s.first)),
        ),
        _label(context, 'Cronómetro'),
        SegmentedButton<ProjectActivity>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: ProjectActivity.all, label: Text('Todos')),
            ButtonSegment(value: ProjectActivity.running, label: Text('En curso')),
            ButtonSegment(value: ProjectActivity.paused, label: Text('Pausados')),
          ],
          selected: {f.activity},
          onSelectionChanged: (s) => set(f.copyWith(activity: s.first)),
        ),
        const SizedBox(height: AppSpacing.sm),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Con tiempo por subir'),
          subtitle: const Text('Jira, desde 1 minuto sin enviar.'),
          value: f.onlyUploadable,
          onChanged: (v) => set(f.copyWith(onlyUploadable: v)),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Arrastran tiempo de otro día'),
          subtitle: const Text('Sin subir, de un día anterior.'),
          value: f.onlyCarried,
          onChanged: (v) => set(f.copyWith(onlyCarried: v)),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Ocultar finalizados'),
          subtitle: const Text('Salvo si corren o tienen tiempo por subir.'),
          value: f.hideDone,
          onChanged: (v) => set(f.copyWith(hideDone: v)),
        ),
      ],
    );
  }
}
