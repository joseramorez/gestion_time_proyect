import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_time_proyect/widgets/inputs/robust_paste.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<TextEditingController> pumpField(WidgetTester tester) async {
    final controller = TextEditingController(text: 'ab');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RobustPaste(
          child: TextField(controller: controller, autofocus: true),
        ),
      ),
    ));
    await tester.pump();
    controller.selection = const TextSelection.collapsed(offset: 1);
    return controller;
  }

  Future<void> ctrlV(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('Ctrl+V pega en la posición del cursor', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData' ? {'text': 'XY'} : null,
    );
    final controller = await pumpField(tester);
    await ctrlV(tester);
    expect(controller.text, 'aXYb');
    expect(controller.selection.baseOffset, 3);
  });

  testWidgets('reintenta si el portapapeles falla de forma transitoria',
      (tester) async {
    var calls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method != 'Clipboard.getData') return null;
        if (++calls < 3) throw PlatformException(code: 'Clipboard error');
        return {'text': 'XY'};
      },
    );
    final controller = await pumpField(tester);
    await ctrlV(tester);
    expect(calls, 3);
    expect(controller.text, 'aXYb');
  });
}
