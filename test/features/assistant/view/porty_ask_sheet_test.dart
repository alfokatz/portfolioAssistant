// La hoja "Preguntale a Porty": las preguntas de la pantalla, el campo para
// escribir la suya y que devuelve la pregunta elegida (la que después va al
// chat con su pantalla). Sin traducciones cargadas, los textos son claves.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/models/porty_screen_context.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_composer_field.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_ask_sheet.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription(SubscriptionTier tier)
    : super(
        SubscriptionState(tier: tier, queriesUsed: 0, queriesLimit: 100),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => PortyAvatar.ambientMotion = false);
  tearDownAll(() => PortyAvatar.ambientMotion = true);

  /// Abre la hoja como la abre `PortyAskSheet.show` y guarda lo que devuelve.
  Future<List<String?>> open(
    WidgetTester tester,
    PortyScreenContext screen, {
    SubscriptionTier tier = SubscriptionTier.free,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(375, 667) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    final theme = container.read(
      brightness == Brightness.light
          ? themeDataLightProvider
          : themeDataDarkProvider,
    );
    container.dispose();
    final results = <String?>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionProvider.overrideWith((ref) => _Subscription(tier)),
        ],
        child: MaterialApp(
          theme: theme,
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () async {
                        results.add(
                          await showModalBottomSheet<String>(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            builder: (_) => PortyAskSheet(screen: screen),
                          ),
                        );
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  group('PortyAskSheet', () {
    for (final brightness in Brightness.values) {
      testWidgets('a position: its title, its questions for the plan and the '
          'field (${brightness.name}, iPhone SE)', (tester) async {
        await open(
          tester,
          const PortyScreenContext.position('AAPL'),
          brightness: brightness,
        );
        expect(find.text('porty_ask_title_ticker'), findsOneWidget);
        expect(find.text('porty_ask_position_week'), findsOneWidget);
        expect(find.text('porty_ask_position_weight'), findsOneWidget);
        expect(find.text('porty_ask_position_since_buy'), findsOneWidget);
        // Free: nada que lleve a un paywall.
        expect(find.text('porty_ask_position_analysis'), findsNothing);
        expect(find.byType(AssistantComposerField), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('tapping a question closes the sheet with it', (tester) async {
      final results = await open(
        tester,
        const PortyScreenContext(PortyScreen.allocation),
      );
      await tester.tap(find.text('porty_ask_allocation_drift'));
      await tester.pumpAndSettle();
      expect(results, ['porty_ask_allocation_drift']);
      expect(find.byType(PortyAskSheet), findsNothing);
    });

    testWidgets('send is off until something is written; then it sends the '
        'trimmed question', (tester) async {
      final results = await open(
        tester,
        const PortyScreenContext(PortyScreen.goalDetail, goalLabel: 'Viaje'),
        tier: SubscriptionTier.premium,
      );
      AssistantSendButton send() =>
          tester.widget<AssistantSendButton>(find.byType(AssistantSendButton));
      expect(send().onTap, isNull);

      await tester.enterText(find.byType(TextField), '  ¿Y si aporto 200?  ');
      await tester.pump();
      expect(send().onTap, isNotNull);
      await tester.tap(find.byType(AssistantSendButton));
      await tester.pumpAndSettle();
      expect(results, ['¿Y si aporto 200?']);
    });

    testWidgets('closing it without choosing sends nothing', (tester) async {
      final results = await open(
        tester,
        const PortyScreenContext(PortyScreen.weeklyReport),
      );
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(results, [null]);
    });
  });
}
