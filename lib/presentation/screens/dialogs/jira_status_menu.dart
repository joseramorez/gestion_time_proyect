import 'package:flutter/material.dart';
import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/domain/entities/jira_entities.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:gestion_time_proyect/widgets/widgets.dart';

/// Cambiar el estado de un ticket de Jira con un menú desplegable pegado al control que
/// lo abrió (`context` debe ser el de la etiqueta de estado). Lista los cambios que el flujo
/// del proyecto permite desde el estado actual y ejecuta el elegido. Solo si Jira lo acepta
/// cambia el estado guardado en la app; cualquier problema se avisa con un mensaje.
Future<void> showJiraStatusMenu(
  BuildContext context,
  JiraController jira,
  ProjectsController projects,
  Project project,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final box = context.findRenderObject() as RenderBox?;
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null || !box.attached) return;

  final result = await jira.transitionsFor(project);
  if (!context.mounted) return;
  final current = project.jiraStatus;
  final options = [
    for (final t in result.transitions)
      if (t.toStatus != current) t,
  ];
  if (result.error != null || options.isEmpty) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          result.error ?? 'Jira no permite cambiar el estado desde aquí.',
        ),
      ),
    );
    return;
  }

  final scheme = Theme.of(context).colorScheme;
  final topLeft = box.localToGlobal(Offset(0, box.size.height), ancestor: overlay);
  final bottomRight = box.localToGlobal(
    box.size.bottomRight(Offset.zero),
    ancestor: overlay,
  );
  final chosen = await showMenu<JiraTransition>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    ),
    constraints: const BoxConstraints(minWidth: 180, maxWidth: 280),
    shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
    clipBehavior: Clip.antiAlias,
    elevation: 6,
    items: [
      // el estado vigente: sombreado, con un check al final y sin poder elegirse
      if (current != null)
        PopupMenuItem<JiraTransition>(
          enabled: false,
          height: 44,
          // el sombreado queda separado del borde del menú y con aire alrededor de la
          // etiqueta; la etiqueta conserva la misma sangría (8 + 8) que las demás filas
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: AppRadius.mdAll,
            ),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Flexible(
                  child: JiraStatusChip(
                    status: current,
                    category: project.jiraStatusCategory,
                  ),
                ),
                const Spacer(),
                Icon(AppIcons.current, size: 18, color: scheme.primary),
              ],
            ),
          ),
        ),
      for (final t in options)
        PopupMenuItem<JiraTransition>(
          value: t,
          height: 40,
          child: Align(
            alignment: Alignment.centerLeft,
            child: JiraStatusChip(
              status: t.toStatus,
              category: t.toCategory,
              tooltip: t.name == t.toStatus
                  ? 'Cambiar a ${t.toStatus}'
                  : '${t.name} → ${t.toStatus}',
            ),
          ),
        ),
    ],
  );
  if (chosen == null) return;

  final error = await jira.changeStatus(project, chosen, projects);
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        error ?? '${project.jiraKey}: estado cambiado a ${chosen.toStatus}.',
      ),
    ),
  );
}
