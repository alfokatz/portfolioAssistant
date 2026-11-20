// Las dos líneas de la consulta de mercado gratis bajo una respuesta.
// Correr: flutter test test/features/assistant/view/assistant_market_taste_notice_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_market_taste_notice.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

void main() {
  setUpAll(() {
    final es =
        jsonDecode(File('assets/translations/es-ES.json').readAsStringSync())
            as Map<String, dynamic>;
    Localization.load(const Locale('es', 'ES'), translations: Translations(es));
  });

  Future<void> pump(
    WidgetTester tester, {
    int? remaining,
    bool teaser = false,
    VoidCallback? onSeePremium,
    bool dark = false,
  }) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: container.read(
          dark ? themeDataDarkProvider : themeDataLightProvider,
        ),
        home: Scaffold(
          body: AssistantMarketTasteNotice(
            remaining: remaining,
            teaser: teaser,
            tier: SubscriptionTier.free,
            onSeePremium: onSeePremium ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('a used lookup says how many are left; the last one says so', (
    tester,
  ) async {
    await pump(tester, remaining: 2);
    expect(
      find.text('Consulta de mercado gratis · te quedan 2 este mes'),
      findsOneWidget,
    );
    expect(find.text('Ver Premium'), findsNothing);

    await pump(tester, remaining: 0, dark: true);
    expect(
      find.text('Consulta de mercado gratis · era la última de este mes'),
      findsOneWidget,
    );
  });

  testWidgets('the teaser takes the count from the plan (3 for Free) and '
      '"Ver Premium" is tappable', (tester) async {
    var taps = 0;
    await pump(tester, teaser: true, onSeePremium: () => taps++);

    expect(
      find.text(
        'Con Premium ves precios, gráficos y comparaciones de cualquier '
        'ticker. Tus 3 consultas gratis de este mes ya se usaron.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Ver Premium'));
    expect(taps, 1);
  });

  testWidgets('nothing to say: nothing is drawn', (tester) async {
    await pump(tester);
    expect(find.byType(Text), findsNothing);
  });

  test('hasContent follows the two message fields', () {
    const base = PortfolioQaMessage(role: PortfolioQaRole.assistant);
    expect(AssistantMarketTasteNotice.hasContent(base), isFalse);
    expect(
      AssistantMarketTasteNotice.hasContent(
        base.copyWith(marketTasteRemaining: 0),
      ),
      isTrue,
    );
    expect(
      AssistantMarketTasteNotice.hasContent(base.copyWith(marketTeaser: true)),
      isTrue,
    );
  });
}
