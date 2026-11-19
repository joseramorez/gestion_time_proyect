import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:gestion_time_proyect/widgets/inputs/robust_paste.dart';

/// Como `showDialog`, pero si el diálogo necesita más alto del que tiene la
/// ventana, la agranda lo necesario mientras está abierto. Al cerrarlo, la
/// ventana vuelve a su alto anterior (salvo que el usuario la haya
/// redimensionado mientras tanto).
Future<T?> showFittedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => RobustPaste(child: _WindowFit(child: builder(ctx))),
  );
}

class _WindowFit extends StatefulWidget {
  const _WindowFit({required this.child});

  final Widget child;

  @override
  State<_WindowFit> createState() => _WindowFitState();
}

class _WindowFitState extends State<_WindowFit> {
  final _key = GlobalKey();
  Size? _original;
  Size? _enlarged;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
  }

  Future<void> _fit() async {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    // Altura natural del diálogo (ya incluye el margen vertical del Dialog).
    final needed = box.size.height.ceilToDouble();
    final current = await windowManager.getSize();
    if (needed <= current.height) return;
    _original ??= current;
    _enlarged = Size(current.width, needed);
    await windowManager.setSize(_enlarged!);
  }

  @override
  void dispose() {
    final original = _original, enlarged = _enlarged;
    if (original != null && enlarged != null) {
      () async {
        final now = await windowManager.getSize();
        if ((now.height - enlarged.height).abs() < 1) {
          await windowManager.setSize(original);
        }
      }();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sin límite vertical el diálogo toma su alto natural, que medimos arriba.
    // OverflowBox (a diferencia de UnconstrainedBox) no reporta error de
    // desbordamiento durante el cuadro previo al reajuste de la ventana.
    return OverflowBox(
      minHeight: 0,
      maxHeight: double.infinity,
      child: NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
          return true;
        },
        child: SizeChangedLayoutNotifier(
          child: KeyedSubtree(key: _key, child: widget.child),
        ),
      ),
    );
  }
}
