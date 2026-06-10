import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog.dart';

import '../../helpers/genui_test_helpers.dart';

void main() {
  group('Portfolio Q&A catalog widget smoke', () {
    testWidgets('custom components render without GenUiErrorCard', (
      WidgetTester tester,
    ) async {
      final catalog = PortfolioQaCatalog.build();
      final items = customCatalogItems(catalog, portfolioQaCustomComponentNames);

      for (final item in items) {
        for (var i = 0; i < item.exampleData.length; i++) {
          await pumpCatalogItemExample(
            tester,
            catalog,
            item,
            exampleIndex: i,
            surfaceId: 'portfolio_qa_0',
          );
        }
      }
    });
  });
}
