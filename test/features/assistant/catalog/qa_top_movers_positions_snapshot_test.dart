import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';

import '../../../helpers/genui_test_helpers.dart';

void main() {
  final catalog = AssistantCatalog.build();

  group('QaTopMovers labels its metric by which field is populated', () {
    final item = catalog.items.firstWhere((i) => i.name == 'QaTopMovers');

    testWidgets('pnlPct → "Rendimiento total" (all-time P&L)', (tester) async {
      await pumpCatalogItemExample(tester, catalog, item, exampleIndex: 0);
      expect(find.text('+8.1%'), findsOneWidget);
      expect(find.text('Rendimiento total'), findsNWidgets(2));
      expect(find.textContaining('Variación'), findsNothing);
    });

    testWidgets('changePct + periodLabel → "Variación · <window>"', (tester) async {
      await pumpCatalogItemExample(tester, catalog, item, exampleIndex: 1);
      expect(find.text('+4.3%'), findsOneWidget);
      expect(find.text('-1.8%'), findsOneWidget);
      expect(find.text('Variación · últimos 7 días'), findsNWidgets(2));
      expect(find.text('Rendimiento total'), findsNothing);
    });
  });

  testWidgets('QaPositionsSnapshot renders value, P&L and P&L% from typed fields', (tester) async {
    final item = catalog.items.firstWhere((i) => i.name == 'QaPositionsSnapshot');
    await pumpCatalogItemExample(tester, catalog, item);
    await tester.pumpAndSettle();
    expect(find.text('Valor (6 posiciones)'), findsOneWidget);
    expect(find.text('\$12,450'), findsOneWidget);
    expect(find.text('+\$1,831'), findsOneWidget);
    expect(find.text('+17.2%'), findsOneWidget);
  });
}
