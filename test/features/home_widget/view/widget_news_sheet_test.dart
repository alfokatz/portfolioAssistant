// WidgetNewsSheet: orden, leyenda, estado bloqueado, claro y oscuro, a 375
// de ancho. Los textos salen por clave (sin cargar traducciones).
// Correr: flutter test test/features/home_widget/view
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_items_cache.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_news_sheet.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

final _now = DateTime(2026, 11, 5, 12);

final _items = [
  WidgetCachedItem(
    id: 'a1b2c3d4',
    kind: 'news',
    ticker: 'AAA',
    headline:
        'AAA anuncia una ampliación muy larga de su planta con un titular que ocupa varias líneas en pantallas angostas',
    source: 'Fuente Ejemplo',
    url: 'https://example.com/a',
    publishedAt: _now.subtract(const Duration(hours: 3)),
    expiresAt: _now.add(const Duration(hours: 45)),
  ),
  WidgetCachedItem(
    id: 'e5f6a7b8',
    kind: 'earnings',
    ticker: 'BBB',
    date: DateTime(2026, 11, 9),
    expiresAt: DateTime(2026, 11, 9, 23, 59, 59),
  ),
];

void main() {
  for (final dark in [false, true]) {
    group(dark ? 'dark' : 'light', () {
      Future<void> pump(
        WidgetTester tester, {
        List<WidgetCachedItem>? items,
        WidgetLockedKind? locked,
        void Function(WidgetCachedItem)? onRead,
        void Function(WidgetCachedItem)? onAsk,
        VoidCallback? onSeePlans,
      }) async {
        tester.view.physicalSize = const Size(375, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final themes = ProviderContainer();
        addTearDown(themes.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: themes.read(
              dark ? themeDataDarkProvider : themeDataLightProvider,
            ),
            home: Scaffold(
              body: WidgetNewsSheet(
                items: items ?? _items,
                now: _now,
                locked: locked,
                onRead: onRead,
                onAsk: onAsk,
                onSeePlans: onSeePlans,
              ),
            ),
          ),
        );
      }

      testWidgets('items in order, legend, actions only on the first',
          (tester) async {
        final read = <String>[];
        final asked = <String>[];
        await pump(
          tester,
          onRead: (i) => read.add(i.id),
          onAsk: (i) => asked.add(i.id),
        );

        expect(find.text('home_widget_sheet_title'), findsOneWidget);
        expect(find.text('home_widget_sheet_legend'), findsOneWidget);
        expect(find.textContaining('AAA anuncia'), findsOneWidget);
        expect(find.textContaining('home_widget_earnings_date'), findsOneWidget);
        expect(find.text('home_widget_ask_porty'), findsOneWidget);

        await tester.tap(find.text('home_widget_read_on'));
        await tester.tap(find.text('home_widget_ask_porty'));
        expect(read, ['a1b2c3d4']);
        expect(asked, ['a1b2c3d4']);
        expect(tester.takeException(), isNull);
      });

      testWidgets('locked state: text and one button', (tester) async {
        var plans = 0;
        await pump(
          tester,
          items: const [],
          locked: WidgetLockedKind.earnings,
          onSeePlans: () => plans++,
        );
        expect(find.text('home_widget_locked_gold'), findsOneWidget);
        await tester.tap(find.text('assistant_quota_nudge_cta'));
        expect(plans, 1);
        expect(find.text('home_widget_ask_porty'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
