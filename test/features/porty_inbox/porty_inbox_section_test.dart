// La bandeja de Porty en la Home: sin nada no ocupa lugar; con insights,
// la frase de Porty, una fila por cada uno y deslizar para ocultar. Sin
// traducciones cargadas, los textos son claves.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/porty_inbox/domain/porty_insight.dart';
import 'package:portfolio_assistant/features/porty_inbox/providers/porty_inbox_provider.dart';
import 'package:portfolio_assistant/features/porty_inbox/view/porty_inbox_section.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_says.dart';

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription()
    : super(
        const SubscriptionState(
          tier: SubscriptionTier.free,
          queriesUsed: 0,
          queriesLimit: 20,
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _concentration = PortyInsight(
  kind: PortyInsightKind.concentration,
  subject: 'NVDA',
  tone: PortyInsightTone.neutral,
  score: 70,
  ticker: 'NVDA',
  numbers: {'weight': 45},
);

const _goal = PortyInsight(
  kind: PortyInsightKind.goalBehind,
  subject: 'g1',
  tone: PortyInsightTone.attention,
  score: 80,
  goalLabel: 'Viaje',
  numbers: {'required': 320, 'planned': 250},
);

void main() {
  setUpAll(() => PortyAvatar.ambientMotion = false);
  tearDownAll(() => PortyAvatar.ambientMotion = true);

  Future<ProviderContainer> pump(
    WidgetTester tester,
    List<PortyInsight> insights, {
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(375, 667) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final themes = ProviderContainer();
    final theme = themes.read(
      brightness == Brightness.light
          ? themeDataLightProvider
          : themeDataDarkProvider,
    );
    themes.dispose();
    final container = ProviderContainer(
      overrides: [
        subscriptionProvider.overrideWith((ref) => _Subscription()),
        portyInsightsProvider.overrideWith((ref) {
          final hidden = ref.watch(portyInboxHiddenProvider);
          return [
            for (final i in insights)
              if (!hidden.containsKey(i.id)) i,
          ];
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: SingleChildScrollView(child: PortyInboxSection()),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  group('PortyInboxSection', () {
    testWidgets('with nothing to mark it takes no space', (tester) async {
      await pump(tester, const []);
      expect(find.byType(PortySays), findsNothing);
      expect(tester.getSize(find.byType(PortyInboxSection)).height, 0);
    });

    for (final brightness in Brightness.values) {
      testWidgets('with insights: what Porty says and one row each '
          '(${brightness.name}, iPhone SE)', (tester) async {
        await pump(tester, const [_goal, _concentration], brightness: brightness);
        expect(find.text('porty_inbox_title_many'), findsOneWidget);
        expect(find.text('porty_inbox_goal_behind_title'), findsOneWidget);
        expect(find.text('porty_inbox_concentration_title'), findsOneWidget);
        // Algo pide atención: Porty preocupado.
        expect(
          tester.widget<PortySays>(find.byType(PortySays)).mood,
          PortyAvatarState.concerned,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('swiping a row hides it for a week', (tester) async {
      final container = await pump(tester, const [_goal, _concentration]);
      await tester.drag(
        find.text('porty_inbox_concentration_title'),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('porty_inbox_concentration_title'), findsNothing);
      expect(find.text('porty_inbox_title_one'), findsOneWidget);
      expect(
        container.read(portyInboxHiddenProvider.notifier).activeIds,
        {'concentration:NVDA'},
      );
    });
  });
}
