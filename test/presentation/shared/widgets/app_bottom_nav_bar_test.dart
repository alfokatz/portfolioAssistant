// La barra de pestañas: con el interruptor `daily_brief` apagado son las
// cuatro de siempre (mismos rótulos, mismo orden); prendido, cinco con
// Noticias y Perfil, y el punto de "hay algo nuevo".
// Correr: flutter test test/presentation/shared/widgets/app_bottom_nav_bar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_bottom_nav_bar.dart';

ThemeData _theme(Brightness b) {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c.read(
    b == Brightness.dark ? themeDataDarkProvider : themeDataLightProvider,
  );
}

Future<List<AppNavDestination>> _pump(
  WidgetTester tester, {
  bool showNews = false,
  bool badge = false,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(600, 667);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final taps = <AppNavDestination>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: _theme(brightness),
      home: Scaffold(
        bottomNavigationBar: AppBottomNavBar(
          current: AppNavDestination.home,
          showNews: showNews,
          newsBadge: badge,
          onSelect: taps.add,
        ),
      ),
    ),
  );
  return taps;
}

void main() {
  testWidgets('switch off: the four tabs of always, no news, no badge', (
    tester,
  ) async {
    await _pump(tester, badge: true);
    // Sin traducciones cargadas, el rótulo es la clave.
    for (final k in [
      'nav_home',
      'nav_assistant',
      'nav_goals',
      'nav_settings',
    ]) {
      expect(find.text(k), findsOneWidget);
    }
    expect(find.text('nav_news'), findsNothing);
    expect(find.text('nav_profile'), findsNothing);
    expect(find.byKey(const Key('nav_news_badge')), findsNothing);
    final xs = [
      for (final k in [
        'nav_home',
        'nav_assistant',
        'nav_goals',
        'nav_settings',
      ])
        tester.getCenter(find.text(k)).dx,
    ];
    expect(xs, [...xs]..sort());
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'switch on: five tabs with Porty in the middle (${brightness.name})',
      (tester) async {
        final taps = await _pump(
          tester,
          showNews: true,
          badge: true,
          brightness: brightness,
        );
        final order = [
          'nav_home',
          'nav_news',
          'nav_assistant',
          'nav_goals',
          'nav_profile',
        ];
        final xs = [for (final k in order) tester.getCenter(find.text(k)).dx];
        expect(xs, [...xs]..sort());
        // Porty (el 3.º de 5) queda en el centro de la pantalla.
        expect(xs[2], closeTo(300, 1));
        expect(find.text('nav_settings'), findsNothing);
        expect(find.byKey(const Key('nav_news_badge')), findsOneWidget);
        await tester.tap(find.text('nav_news'));
        expect(taps, [AppNavDestination.news]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('switch on without news to see: no badge', (tester) async {
    await _pump(tester, showNews: true);
    expect(find.byKey(const Key('nav_news_badge')), findsNothing);
  });
}
