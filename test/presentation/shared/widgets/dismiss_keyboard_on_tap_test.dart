import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/dismiss_keyboard_on_tap.dart';

/// Tocar afuera de un campo baja el teclado (el numérico de iOS no tiene
/// tecla para cerrarlo); tocar un botón, el mismo campo o scrollear, no.
void main() {
  late FocusNode focus;
  var pressed = 0;

  Future<void> pump(WidgetTester tester) async {
    focus = FocusNode();
    addTearDown(focus.dispose);
    pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => DismissKeyboardOnTap(child: child!),
        home: Scaffold(
          body: ListView(
            children: [
              TextField(
                key: const Key('field'),
                focusNode: focus,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 300, child: Text('fondo')),
              FilledButton(
                onPressed: () => pressed++,
                child: const Text('Agregar'),
              ),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('tocar afuera del campo baja el teclado', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await tester.tap(find.text('fondo'));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
  });

  testWidgets('tocar el mismo campo no lo baja', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('un botón sigue funcionando con el teclado arriba', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    await tester.tap(find.text('Agregar'));
    await tester.pump();
    expect(pressed, 1);
  });

  testWidgets('scrollear no baja el teclado', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    await tester.drag(find.text('fondo'), const Offset(0, -40));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
  });
}
