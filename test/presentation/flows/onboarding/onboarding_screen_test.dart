import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/onboarding_screen.dart';

/// Sin easy_localization cargado, `.tr()` devuelve la key: los textos se
/// buscan por key.
const _next = 'onboarding_next';

/// iPhone SE (2.ª/3.ª gen.) en puntos.
const _seSize = Size(375, 667);

Widget _app({double textScale = 1}) {
  final container = ProviderContainer();
  final theme = container.read(themeDataLightProvider);
  container.dispose();
  return ProviderScope(
    child: MaterialApp(
      theme: theme,
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
      home: const OnboardingScreen(),
    ),
  );
}

void main() {
  setUpAll(() => PortyAvatar.ambientMotion = false);

  void setSize(WidgetTester tester) {
    tester.view.physicalSize = _seSize * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
  }

  Future<void> goToPage(WidgetTester tester, int page) async {
    for (var i = 0; i < page; i++) {
      await tester.tap(find.text(_next));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('recorre las páginas hasta cargar la cartera', (tester) async {
    setSize(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('onboarding_welcome_title'), findsOneWidget);
    // Lo que se le puede pedir a Porty, desde la primera pantalla.
    expect(find.text('onboarding_welcome_prompt_goal'), findsOneWidget);

    final titles = [
      'onboarding_dashboard_title',
      'onboarding_assistant_title',
      'onboarding_goals_title',
      'onboarding_alerts_title',
      'onboarding_finish_title',
    ];
    for (final title in titles) {
      await goToPage(tester, 1);
      expect(find.text(title), findsOneWidget);
    }

    expect(OnboardingScreen.pageCount, titles.length + 1);
    expect(find.text('onboarding_finish_add_title'), findsOneWidget);
    expect(find.text('onboarding_skip'), findsNothing);
  });

  testWidgets('los casos de uso del chat cambian la conversación', (
    tester,
  ) async {
    setSize(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await goToPage(tester, 2);

    expect(find.text('onboarding_chat_portfolio_question'), findsOneWidget);

    await tester.tap(find.text('onboarding_use_case_market'));
    await tester.pumpAndSettle();
    expect(find.text('onboarding_chat_market_question'), findsOneWidget);
    expect(find.text('onboarding_chat_portfolio_question'), findsNothing);

    await tester.tap(find.text('onboarding_use_case_analysis'));
    await tester.pumpAndSettle();
    expect(find.text('onboarding_chat_analysis_question'), findsOneWidget);
  });

  testWidgets('entra en un SE con texto grande sin desbordar', (tester) async {
    setSize(tester);
    await tester.pumpWidget(_app(textScale: 1.3));
    await tester.pumpAndSettle();
    for (var page = 1; page < OnboardingScreen.pageCount; page++) {
      await goToPage(tester, 1);
    }
    expect(tester.takeException(), isNull);
  });
}
