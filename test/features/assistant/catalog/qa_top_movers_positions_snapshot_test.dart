import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';

import '../../../helpers/genui_test_helpers.dart';

void main() {
  final catalog = AssistantCatalog.build();

  group('QaTopMovers labels its metric by which field is populated', () {
    final item = catalog.items.firstWhere((i) => i.name == 'QaTopMovers');

    testWidgets('pnlPct → "Rendimiento total" (all-time P&L)', (tester) async {
      await pumpCatalogItemExample(tester, catalog, item, exampleIndex: 0);
      await tester.pumpAndSettle();
      expect(find.text('AAPL'), findsOneWidget);
      expect(find.text('TSLA'), findsOneWidget);
      expect(find.text('8.1%'), findsOneWidget);
      expect(find.text('3.2%'), findsOneWidget);
      expect(find.text('RENDIMIENTO TOTAL'), findsOneWidget);
      expect(find.textContaining('VARIACIÓN'), findsNothing);
    });

    testWidgets('changePct + periodLabel → "Variación · <window>"', (
      tester,
    ) async {
      await pumpCatalogItemExample(tester, catalog, item, exampleIndex: 1);
      await tester.pumpAndSettle();
      expect(find.text('4.3%'), findsOneWidget);
      expect(find.text('1.8%'), findsOneWidget);
      expect(find.text('VARIACIÓN · ÚLTIMOS 7 DÍAS'), findsOneWidget);
      expect(find.text('RENDIMIENTO TOTAL'), findsNothing);
    });
  });

  testWidgets('QaPositionsSnapshot renders the hero, P&L chip and allocation', (
    tester,
  ) async {
    final item = catalog.items.firstWhere(
      (i) => i.name == 'QaPositionsSnapshot',
    );
    await pumpCatalogItemExample(tester, catalog, item);
    await tester.pumpAndSettle();
    expect(find.text('TU PORTFOLIO'), findsOneWidget);
    expect(find.text('6 posiciones'), findsOneWidget);
    expect(find.text('\$12,450'), findsOneWidget);
    expect(find.text('\$1,831 · 17.2%'), findsOneWidget);
    expect(find.text('desde la compra'), findsOneWidget);
    // Top 5 + "Otros" con el resto (TSLA 3.5%).
    expect(find.byType(QaSegmentedBar), findsOneWidget);
    expect(find.text('NVDA'), findsOneWidget);
    expect(find.text('Otros'), findsOneWidget);
    expect(find.text('TSLA'), findsNothing);
  });
}
