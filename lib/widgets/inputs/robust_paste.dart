import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _RobustPasteIntent extends Intent {
  const _RobustPasteIntent();
}

/// Reemplaza Ctrl+V / Shift+Insert de los campos de texto por un pegado que
/// reintenta. En Windows el portapapeles puede estar bloqueado un instante por
/// otro programa (historial del portapapeles, gestores, etc.); el pegado
/// estándar hace un solo intento y, si falla, no pega nada sin avisar.
class RobustPaste extends StatelessWidget {
  const RobustPaste({super.key, required this.child});

  final Widget child;

  static const _attempts = 6;
  static const _retryDelay = Duration(milliseconds: 80);

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyV, control: true):
            _RobustPasteIntent(),
        SingleActivator(LogicalKeyboardKey.keyV, meta: true):
            _RobustPasteIntent(),
        SingleActivator(LogicalKeyboardKey.insert, shift: true):
            _RobustPasteIntent(),
      },
      child: Actions(
        actions: {
          _RobustPasteIntent: CallbackAction<_RobustPasteIntent>(
            onInvoke: (_) {
              _paste();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }

  static Future<void> _paste() async {
    final state = primaryFocus?.context
        ?.findAncestorStateOfType<EditableTextState>();
    if (state == null || state.widget.readOnly) return;

    for (var i = 1; i <= _attempts; i++) {
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text;
        if (text == null || text.isEmpty) return;
        _insert(state, text);
        return;
      } catch (e) {
        debugPrint('Portapapeles: intento $i/$_attempts falló: $e');
        await Future<void>.delayed(_retryDelay);
      }
    }
  }

  static void _insert(EditableTextState state, String text) {
    final value = state.textEditingValue;
    final sel = value.selection;
    final start = sel.isValid ? sel.start : value.text.length;
    final end = sel.isValid ? sel.end : value.text.length;
    state.userUpdateTextEditingValue(
      TextEditingValue(
        text: value.text.replaceRange(start, end, text),
        selection: TextSelection.collapsed(offset: start + text.length),
      ),
      SelectionChangedCause.keyboard,
    );
  }
}
