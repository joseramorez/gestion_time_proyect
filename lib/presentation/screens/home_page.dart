import 'package:flutter/material.dart';
import 'package:gestion_time_proyect/core/services/startup_service.dart';
import 'package:gestion_time_proyect/core/services/window_service.dart';
import 'package:gestion_time_proyect/presentation/screens/close_guard.dart';
import 'package:gestion_time_proyect/presentation/screens/compact_view.dart';
import 'package:gestion_time_proyect/presentation/screens/day_progress_bar.dart';
import 'package:gestion_time_proyect/presentation/screens/list_filter_bar.dart';
import 'package:gestion_time_proyect/presentation/viewModels/daily_controller.dart';

import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/widgets/widgets.dart';
import 'package:gestion_time_proyect/presentation/viewModels/jira_controller.dart';
import 'package:gestion_time_proyect/core/utils/duration_format.dart';
import 'package:gestion_time_proyect/domain/entities/day_key.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:gestion_time_proyect/presentation/screens/dialogs/day_cut_dialog.dart';
import 'package:gestion_time_proyect/presentation/screens/dialogs/jira_cut_dialog.dart';
import 'package:gestion_time_proyect/presentation/screens/dialogs/jira_dialog.dart';
import 'package:gestion_time_proyect/presentation/screens/dialogs/jira_status_menu.dart';
import 'package:gestion_time_proyect/presentation/screens/dialogs/start_in_progress_dialog.dart';
import 'package:gestion_time_proyect/domain/usecases/in_progress_rules.dart';
import 'package:gestion_time_proyect/presentation/screens/dialogs/project_form_dialog.dart';
import 'package:gestion_time_proyect/presentation/screens/dialogs/project_info_dialog.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.jira,
    required this.daily,
    required this.window,
    this.startup,
    this.autoSyncInterval = const Duration(hours: 2),
  });

  final ProjectsController controller;
  final JiraController jira;
  final DailyController daily;
  final WindowService window;

  /// Arranque con el equipo. Si es null (p. ej. en pruebas) la opción no se muestra.
  final StartupService? startup;

  /// Cada cuánto se sincroniza Jira solo; se muestra en la leyenda del ajuste.
  final Duration autoSyncInterval;

  /// Aviso del botón de play de un ticket con tiempo de un día anterior sin subir.
  static String startBlockedTooltip(Project project) {
    final d = dayStartOf(project.timeSinceDay!);
    String two(int n) => n.toString().padLeft(2, '0');
    final day = '${two(d.day)}/${two(d.month)}';
    return project.jiraKey != null
        ? 'Sube o limpia primero el tiempo del $day de este ticket'
        : 'Limpia primero el tiempo del $day de este ticket';
  }

  /// Textos del botón de la vista simple (el segundo explica por qué está desactivado).
  static const compactTooltip = 'Vista simple: solo el ticket en curso';
  static const compactDisabledTooltip =
      'La vista simple necesita un ticket en curso: inicia uno primero';

  /// Pasa a la vista simple (solo el ticket en curso). Primero cambia lo que se
  /// dibuja y luego el tamaño de la ventana, para no mostrar la vista completa en
  /// una ventana diminuta.
  Future<void> _enterCompact() async {
    // Sin ticket en curso no hay nada que mostrar (el botón ya está desactivado;
    // esto es solo una segunda barrera).
    if (!controller.canUseCompactMode) return;
    controller.setCompactMode(true);
    await window.enterCompact(opacity: controller.compactOpacity);
  }

  /// Vuelve a la vista completa. Al revés que al entrar: primero se agranda la
  /// ventana y luego se dibuja la vista completa.
  Future<void> _exitCompact() async {
    try {
      await window.exitCompact(
        opacity: controller.opacity,
        alwaysOnTop: controller.alwaysOnTop,
      );
    } catch (e) {
      // Se registra y se sigue: lo importante es que la interfaz pueda salir.
      debugPrint('No se pudo restaurar la ventana: $e');
    } finally {
      // Pase lo que pase con la ventana nativa, la vista cambia: la interfaz nunca
      // debe quedarse atrapada en la vista simple.
      controller.setCompactMode(false);
    }
  }

  /// Transparencia de la vista completa: se aplica a la ventana al instante.
  Future<void> _applyOpacity(double value, {required bool persist}) async {
    await controller.setOpacity(value, persist: persist);
    await window.setOpacity(controller.opacity);
  }

  /// Transparencia de la vista simple: solo se guarda; se aplica al entrar en ella
  /// (este diálogo se abre desde la vista completa, así que no hay nada que
  /// cambiar en la ventana mientras tanto).
  Future<void> _applyCompactOpacity(double value, {required bool persist}) =>
      controller.setCompactOpacity(value, persist: persist);

  Future<void> _setAlwaysOnTop(bool value) async {
    await window.setAlwaysOnTop(value);
    await controller.setAlwaysOnTop(value);
  }

  void _showWindowDialog(BuildContext context) {
    showFittedDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ventana'),
        content: ListenableBuilder(
          listenable: controller,
          builder: (_, _) => AppDialogBody(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OpacitySlider(
                  label: 'Transparencia · vista completa',
                  value: controller.opacity,
                  onChanged: (v) => _applyOpacity(v, persist: false),
                  onChangeEnd: (v) => _applyOpacity(v, persist: true),
                ),
                _OpacitySlider(
                  label: 'Transparencia · vista simple',
                  value: controller.compactOpacity,
                  onChanged: (v) => _applyCompactOpacity(v, persist: false),
                  onChangeEnd: (v) => _applyCompactOpacity(v, persist: true),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mantener encima de otras ventanas'),
                  subtitle: const Text(
                    'Solo la vista completa; la vista simple siempre va encima.',
                  ),
                  value: controller.alwaysOnTop,
                  onChanged: _setAlwaysOnTop,
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sincronizar Jira automáticamente'),
                  subtitle: Text(
                    'Trae tus tickets ${formatEvery(autoSyncInterval)}, con la app '
                    'abierta y la sesión de Jira iniciada.',
                  ),
                  value: controller.autoSyncJira,
                  onChanged: controller.setAutoSyncJira,
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Confirmar al cerrar'),
                  subtitle: const Text(
                    'Pregunta antes de cerrar; con tiempos corriendo, permite '
                    'pausarlos o subirlos a Jira.',
                  ),
                  value: controller.confirmClose,
                  onChanged: controller.setConfirmClose,
                ),
                if (startup != null) _StartupSwitch(service: startup!),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _applyOpacity(1.0, persist: true);
              _applyCompactOpacity(1.0, persist: true);
            },
            child: const Text('Restablecer'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CloseGuard(
      controller: controller,
      daily: daily,
      window: window,
      beforePrompt: () async {
        if (controller.compactMode) await _exitCompact();
      },
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, daily]),
      builder: (context, _) {
        // Vista simple: no hay nada más que el ticket en curso.
        if (controller.compactMode) {
          return CompactView(
            controller: controller,
            onExit: _exitCompact,
            onFit: (content, client) =>
                window.fitCompact(content: content, client: client),
            // Transparencia propia de la vista simple: se aplica a la ventana al arrastrar.
            onOpacity: window.setOpacity,
          );
        }
        final projects = controller.visibleProjects;
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 52,
            titleSpacing: 10,
            // Si el texto "my-jira-work-time" no cabe junto a los botones, queda solo el logo.
            title: LayoutBuilder(
              builder: (context, c) => Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/icon/app_icon.png',
                      width: 24,
                      height: 24,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  if (c.maxWidth >= 94) ...[
                    const SizedBox(width: AppSpacing.sm),
                    const Flexible(
                      child: Text(
                        'my-jira-work-time',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppFontSize.appBar,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              AppIconButton(
                icon: AppIcons.pin,
                tooltip: controller.canUseCompactMode
                    ? compactTooltip
                    : compactDisabledTooltip,
                onPressed: controller.canUseCompactMode ? _enterCompact : null,
              ),
              AppIconButton(
                icon: AppIcons.jira,
                tooltip: 'Jira',
                onPressed: () => showJiraDialog(context, jira, controller),
              ),
              AppIconButton(
                icon: AppIcons.settings,
                tooltip: 'Ventana: transparencia y superposición',
                onPressed: () => _showWindowDialog(context),
              ),
              AppIconButton(
                icon: AppIcons.add,
                variant: AppIconButtonVariant.filled,
                tooltip: 'Agregar proyecto o ticket',
                onPressed: () => showProjectForm(context, controller),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
          ),
          body: Column(
            children: [
              DayProgressBar(
                daily: daily,
                onCut: () => showDayCutDialog(context, daily, jira, controller),
              ),
              if (controller.projects.isNotEmpty)
                ListFilterBar(controller: controller),
              Expanded(
                child: controller.projects.isNotEmpty && projects.isEmpty
                    ? AppEmptyState(
                        icon: AppIcons.filter,
                        title: 'Ningún ticket coincide',
                        message:
                            'Prueba con otra búsqueda o quita los filtros.',
                        actionLabel: 'Limpiar filtros',
                        onAction: controller.clearFilter,
                      )
                    : projects.isEmpty
                    ? AppEmptyState(
                        icon: AppIcons.timer,
                        title: 'Aún no hay proyectos',
                        message:
                            'Agrega un proyecto o ticket para medir su tiempo.',
                        actionLabel: 'Agregar',
                        actionIcon: AppIcons.add,
                        onAction: () => showProjectForm(context, controller),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          TileLimits.listInset,
                          AppSpacing.xs,
                          TileLimits.listInset,
                          AppSpacing.md,
                        ),
                        itemCount: projects.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (_, i) => ProjectTile(
                          project: projects[i],
                          controller: controller,
                          jira: jira,
                          startBlockedTooltip: daily.isStartBlocked(projects[i])
                              ? startBlockedTooltip(projects[i])
                              : null,
                          // Un ticket con tiempo de otro día se sube desde el corte del
                          // día, que lo anota en el día trabajado.
                          onCutDay: daily.carriesOlderTime(projects[i])
                              ? () => showDayCutDialog(
                                  context,
                                  daily,
                                  jira,
                                  controller,
                                )
                              : null,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Control deslizante de transparencia con su título y el porcentaje.
/// Interruptor de "Iniciar con el equipo". Lee el estado real del sistema al abrirse
/// y, si el cambio falla (permisos, equipo restringido), vuelve al valor anterior y
/// lo avisa en el propio texto en vez de dejar el interruptor mintiendo.
class _StartupSwitch extends StatefulWidget {
  const _StartupSwitch({required this.service});

  final StartupService service;

  @override
  State<_StartupSwitch> createState() => _StartupSwitchState();
}

class _StartupSwitchState extends State<_StartupSwitch> {
  bool _value = false;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      _value = await widget.service.isEnabled();
    } catch (e) {
      _error = 'No se pudo leer el estado del arranque';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _change(bool value) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.setEnabled(value);
      _value = value;
    } catch (e) {
      _error = 'No se pudo cambiar: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: const Text('Iniciar con el equipo'),
      subtitle: Text(_error ?? 'Abre la app al iniciar sesión.'),
      value: _value,
      onChanged: _busy ? null : _change,
    );
  }
}

class _OpacitySlider extends StatelessWidget {
  const _OpacitySlider({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppFontSize.label,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                min: ProjectsController.minOpacity,
                max: 1.0,
                value: value,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
            SizedBox(width: 40, child: Text('${(value * 100).round()}%')),
          ],
        ),
      ],
    );
  }
}

/// Tarjeta de un proyecto/ticket. La fila de controles se reparte así (medidas en
/// `TileLimits`): `[play] [cronómetro] [— estado de Jira —] [acciones]`; todo
/// tiene ancho fijo salvo el estado, que ocupa el hueco central.
class ProjectTile extends StatelessWidget {
  const ProjectTile({
    super.key,
    required this.project,
    required this.controller,
    required this.jira,
    this.startBlockedTooltip,
    this.onCutDay,
  });

  final Project project;
  final ProjectsController controller;
  final JiraController jira;

  /// Si no es `null`, el ticket trae tiempo de un día anterior sin subir: no se puede
  /// iniciar (pausar sí) y este texto explica por qué.
  final String? startBlockedTooltip;

  /// Si no es `null`, el botón de corte abre el corte del día en vez del corte por ticket
  /// (para anotar el tiempo en el día trabajado).
  final VoidCallback? onCutDay;

  /// Play. Si el ticket es de Jira y sigue en «Backlog» / «Selected for Development» (y hay
  /// sesión con permiso de escritura), pregunta si además se pasa a «en curso». El cronómetro
  /// arranca enseguida con «Solo iniciar» o «Poner en curso»; un fallo al cambiar el estado
  /// solo se avisa, nunca detiene el cronómetro.
  Future<void> _play(BuildContext context) async {
    final offer =
        const ShouldOfferInProgress()(project) &&
        jira.signedIn &&
        jira.canWrite;
    if (!offer) {
      await controller.start(project);
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final choice = await showStartInProgressDialog(context, project);
    if (choice == StartChoice.cancel) return;
    await controller.start(project);
    if (choice != StartChoice.startInProgress) return;

    final found = await jira.transitionsFor(project);
    final pick = const PickInProgressTransition()(found.transitions);
    String? error = found.error;
    if (error == null && pick != null) {
      error = await jira.changeStatus(project, pick, controller);
    } else if (error == null) {
      // No hay un «en curso» claro: se deja elegir al usuario.
      if (context.mounted) {
        await showJiraStatusMenu(context, jira, controller, project);
      }
      return;
    }
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? '${project.jiraKey}: estado cambiado a ${pick!.toStatus}.'
              : 'El cronómetro corre, pero no se pudo cambiar el estado: $error',
        ),
      ),
    );
  }

  /// Corte hacia Jira. Sin sesión (o sin permiso de escritura) abre el diálogo
  /// de Jira, que explica qué falta.
  void _cut(BuildContext context) {
    if (onCutDay != null) {
      onCutDay!();
    } else if (!jira.signedIn || !jira.session!.canWrite) {
      showJiraDialog(context, jira, controller);
    } else {
      showJiraCutDialog(context, jira, controller, project);
    }
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = project.elapsed();
    final running = project.isRunning;
    final scheme = Theme.of(context).colorScheme;
    final tooShort = elapsed.inSeconds < JiraController.minLogSeconds;

    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: Curves.easeOut,
      padding: const EdgeInsets.fromLTRB(
        TileLimits.paddingLeft,
        AppSpacing.sm,
        TileLimits.paddingRight,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: running ? scheme.primaryContainer : scheme.surfaceContainerLow,
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: running
              ? scheme.primary.withValues(alpha: 0.55)
              : Colors.transparent,
          width: TileLimits.border,
        ),
      ),
      // El nombre ocupa todo el ancho; debajo van el cronómetro, el estado y los
      // controles.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, right: AppSpacing.sm),
            child: Text(
              project.name,
              maxLines: TileLimits.nameMaxLines,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: AppFontSize.body,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              AppIconButton(
                icon: running ? AppIcons.pause : AppIcons.play,
                variant: running
                    ? AppIconButtonVariant.filled
                    : AppIconButtonVariant.tonal,
                size: AppIconButtonSize.large,
                tooltip: running
                    ? 'Pausar'
                    : startBlockedTooltip ??
                          (elapsed == Duration.zero ? 'Iniciar' : 'Reanudar'),
                onPressed: running
                    ? () => controller.pause(project)
                    : startBlockedTooltip != null
                    ? null
                    : () => _play(context),
              ),
              const SizedBox(width: TileLimits.gap),
              // Cronómetro (y "En Jira"): ancho máximo fijo y, si no cabe, se reduce
              // un poco en vez de empujar los botones.
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: TileLimits.timeMaxWidth,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatDuration(elapsed),
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontSize: AppFontSize.timer,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          color: running ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                      if (project.jiraLoggedMs > 0)
                        Tooltip(
                          message: 'Tiempo ya enviado a Jira con el corte',
                          child: Text(
                            'En Jira: ${formatWorkDuration(Duration(milliseconds: project.jiraLoggedMs))}',
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: AppFontSize.caption,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Estado de Jira: en el centro de la tarjeta, en el hueco entre el
              // cronómetro y los botones. En una entrada manual el hueco queda vacío.
              Expanded(
                child: Center(
                  child: project.jiraStatus != null
                      ? Builder(
                          // el menú se despliega pegado a la etiqueta
                          builder: (chipContext) => JiraStatusChip(
                            status: project.jiraStatus!,
                            category: project.jiraStatusCategory,
                            onTap: project.jiraKey == null
                                ? null
                                : () => showJiraStatusMenu(
                                    chipContext,
                                    jira,
                                    controller,
                                    project,
                                  ),
                          ),
                        )
                      : project.jiraKey != null
                      ? const JiraStatusChip(
                          status: 'Sin sincronizar',
                          pending: true,
                          tooltip:
                              'Aún no se trajo el estado de Jira. Pulsa Sincronizar en el diálogo de Jira.',
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              AppIconButton(
                icon: AppIcons.reset,
                size: AppIconButtonSize.compact,
                tooltip: 'Limpiar tiempo',
                onPressed: elapsed == Duration.zero && !running
                    ? null
                    : () => controller.clear(project),
              ),
              if (project.jiraKey != null)
                AppIconButton(
                  icon: AppIcons.cutToJira,
                  size: AppIconButtonSize.compact,
                  tooltip: tooShort
                      ? 'Cortar y enviar a Jira (necesita al menos 1 minuto)'
                      : 'Cortar y enviar a Jira',
                  onPressed: tooShort ? null : () => _cut(context),
                ),
              AppIconButton(
                icon: AppIcons.info,
                size: AppIconButtonSize.compact,
                tooltip: 'Información',
                onPressed: () =>
                    showProjectInfo(context, controller, project, jira: jira),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
