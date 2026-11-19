import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestion_time_proyect/config/theme/theme.dart';
import 'package:gestion_time_proyect/core/utils/duration_format.dart';
import 'package:gestion_time_proyect/domain/entities/project.dart';
import 'package:gestion_time_proyect/presentation/viewModels/projects_controller.dart';
import 'package:gestion_time_proyect/widgets/widgets.dart';

/// Vista simple: solo el ticket que está corriendo, con su nombre y su tiempo, y un
/// deslizador de **transparencia propia** (la de esta vista, separada de la de la
/// vista completa). No hay nada más que pulsar, para que no se pueda tocar nada por
/// accidente mientras la ventana flota sobre otras.
///
/// **Solo existe mientras hay un ticket en curso**: sin uno no tendría sentido. A
/// ella se entra únicamente con un ticket corriendo (el pin de la pantalla principal
/// está desactivado si no lo hay) y, si por lo que sea dejara de haberlo, la vista
/// **sale sola** a la vista completa.
///
/// **Salir (`onExit`) siempre es posible y evidente**, de tres maneras:
///  * el **botón** de la esquina (siempre visible);
///  * **doble clic** sobre el nombre o el tiempo;
///  * la tecla **Esc**.
/// El botón existe porque doble clic y Esc no se descubren solos: una vista sin
/// salida visible deja al usuario atrapado.
///
/// **El tamaño de la ventana se ajusta solo al contenido.** La vista mide su altura
/// natural (nombre + tiempo + deslizador + márgenes) y la comunica por `onFit` junto
/// con el tamaño de su propia área (`client`); quien tiene la ventana nativa descuenta
/// lo que ocupa la barra de título *en ese equipo* (que cambia con la escala de
/// pantalla) y fija la altura exacta.
///
/// El nombre ocupa una línea (`CompactLimits.nameMaxLines`) y se recorta con "…".
class CompactView extends StatefulWidget {
  const CompactView({
    super.key,
    required this.controller,
    required this.onExit,
    this.onFit,
    this.onOpacity,
  });

  final ProjectsController controller;
  final VoidCallback onExit;

  /// Tamaño óptimo del contenido (`content`, con el ancho de `WindowLimits.compact`)
  /// y tamaño actual del área de la vista (`client`).
  final void Function(Size content, Size client)? onFit;

  /// Se llama mientras se arrastra el deslizador, para aplicar la transparencia a la
  /// ventana al instante. La vista ya actualiza y guarda la preferencia en el
  /// controlador; esto es solo para la ventana nativa.
  final ValueChanged<double>? onOpacity;

  static const hint = 'Doble clic (o Esc) para volver a la vista completa';

  /// Texto del botón de salida.
  static const exitTooltip = 'Volver a la vista completa';

  /// Texto del deslizador de transparencia.
  static const opacityTooltip = 'Transparencia de la vista simple';

  /// Margen vertical alrededor del contenido.
  static const verticalPadding = AppSpacing.sm;

  @override
  State<CompactView> createState() => _CompactViewState();
}

class _CompactViewState extends State<CompactView> {
  final _contentKey = GlobalKey();
  Size? _lastContent;
  Size? _lastClient;
  bool _leaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cambió el tamaño de la ventana (o el tema/escala): volver a comprobar el ajuste.
    _scheduleFit();
  }

  void _scheduleFit() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
  }

  void _fit() {
    if (!mounted || widget.onFit == null) return;
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final content = Size(
      WindowLimits.compact.width,
      box.size.height + 2 * CompactView.verticalPadding,
    );
    final client = MediaQuery.sizeOf(context);
    // Ya informado: así el ajuste converge (al cambiar la ventana cambia `client`,
    // pero el `content` es el mismo y quien ajusta no hace nada si ya mide eso).
    if (content == _lastContent && client == _lastClient) return;
    _lastContent = content;
    _lastClient = client;
    widget.onFit!(content, client);
  }

  /// Sin ticket en curso esta vista no tiene sentido: vuelve a la completa (una vez).
  void _leaveSoon() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onExit();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onExit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        body: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final running = widget.controller.projects
                .where((p) => p.isRunning)
                .firstOrNull;
            if (running == null) _leaveSoon();
            return _layout(context, running);
          },
        ),
      ),
    );
  }

  /// Todo el contenido, medido con su altura natural. `OverflowBox` le da altura libre
  /// aunque la ventana aún sea más baja (hasta que se ajuste), así que no hay error de
  /// desbordamiento, y lo deja centrado cuando sobra espacio.
  Widget _layout(BuildContext context, Project? running) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        CompactView.verticalPadding,
        AppSpacing.sm,
        CompactView.verticalPadding,
      ),
      child: OverflowBox(
        maxHeight: double.infinity,
        alignment: Alignment.centerLeft,
        child: NotificationListener<SizeChangedLayoutNotification>(
          onNotification: (_) {
            _scheduleFit();
            return true;
          },
          child: SizeChangedLayoutNotifier(
            child: KeyedSubtree(
              key: _contentKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [_topRow(context, running), _opacityRow(context)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Nombre y tiempo (con doble clic para salir) y, a la derecha, el botón de salida.
  ///
  /// El doble clic va SOLO sobre el nombre y el tiempo: un reconocedor de doble
  /// clic espera ~300 ms a un posible segundo toque, y si envolviera toda la vista
  /// retrasaría ese mismo tiempo los toques en el botón y en el deslizador.
  Widget _topRow(BuildContext context, Project? running) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Tooltip(
            message: CompactView.hint,
            waitDuration: const Duration(milliseconds: 900),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: widget.onExit,
              child: running == null
                  ? _noTicket(context)
                  : _ticket(context, running),
            ),
          ),
        ),
        AppIconButton(
          icon: AppIcons.restoreView,
          size: AppIconButtonSize.compact,
          tooltip: CompactView.exitTooltip,
          onPressed: widget.onExit,
        ),
      ],
    );
  }

  /// Instante previo a salir sola: no debería llegar a verse.
  Widget _noTicket(BuildContext context) {
    return Text(
      'Sin ticket en curso',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: AppFontSize.body,
        fontStyle: FontStyle.italic,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _ticket(BuildContext context, Project running) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: Text(
            running.name,
            maxLines: CompactLimits.nameMaxLines,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: AppFontSize.body,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          formatDuration(running.elapsed()),
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontSize: AppFontSize.compactTimer,
            fontWeight: FontWeight.w700,
            height: 1.15,
            color: scheme.primary,
          ),
        ),
      ],
    );
  }

  /// Deslizador de la transparencia de ESTA vista (`compactOpacity`). Se aplica a la
  /// ventana al instante y se guarda al soltarlo.
  Widget _opacityRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = widget.controller.compactOpacity;
    return Tooltip(
      message: CompactView.opacityTooltip,
      child: SizedBox(
        height: CompactLimits.opacityRowHeight,
        child: Row(
          children: [
            Icon(AppIcons.opacity, size: 14, color: scheme.onSurfaceVariant),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Slider(
                  min: ProjectsController.minOpacity,
                  max: 1.0,
                  value: value,
                  onChanged: (v) {
                    widget.controller.setCompactOpacity(v, persist: false);
                    widget.onOpacity?.call(v);
                  },
                  onChangeEnd: (v) => widget.controller.setCompactOpacity(v),
                ),
              ),
            ),
            SizedBox(
              width: 34,
              child: Text(
                '${(value * 100).round()}%',
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
