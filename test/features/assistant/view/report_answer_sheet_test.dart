// Reportar una respuesta de Porty: elegir un motivo, enviar y que quede el
// evento con el comienzo de la respuesta. Correr:
// flutter test test/features/assistant/view/report_answer_sheet_test.dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/report_answer_sheet.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

import '../../subscription/paywall_test_harness.dart' show FakeProductEvents;

void main() {
  setUpAll(() => PortyAvatar.ambientMotion = false);

  late FakeProductEvents events;

  Future<void> open(WidgetTester tester, String answer) async {
    events = FakeProductEvents();
    final probe = ProviderContainer();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [productEventsProvider.overrideWithValue(events)],
        child: MaterialApp(
          theme: probe.read(themeDataLightProvider),
          home: Consumer(
            builder:
                (context, ref, _) => Scaffold(
                  body: TextButton(
                    onPressed:
                        () => ReportAnswerSheet.show(
                          context,
                          ref,
                          surfaceId: 's-1',
                          answer: answer,
                        ),
                    child: const Text('open'),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('sin motivo no se puede enviar; con motivo guarda el evento '
      'con el extracto recortado', (tester) async {
    await open(tester, 'x' * 1000);
    expect(find.text('assistant_report_title'.tr()), findsOneWidget);

    await tester.tap(find.text('assistant_report_send'.tr()));
    await tester.pumpAndSettle();
    expect(events.of(ProductEvent.aiAnswerReported), isEmpty);

    await tester.tap(find.text('assistant_report_reason_advice'.tr()));
    await tester.pump();
    await tester.tap(find.text('assistant_report_send'.tr()));
    await tester.pumpAndSettle();

    final props = events.of(ProductEvent.aiAnswerReported).single;
    expect(props['reason'], 'advice');
    expect(props['surface_id'], 's-1');
    expect((props['excerpt'] as String).length, ReportAnswerSheet.excerptLength);
  });

  testWidgets('cancelar no guarda nada', (tester) async {
    await open(tester, 'Tu cartera subió 2%.');
    await tester.tap(find.text('assistant_report_cancel'.tr()));
    await tester.pumpAndSettle();
    expect(events.of(ProductEvent.aiAnswerReported), isEmpty);
  });
}
