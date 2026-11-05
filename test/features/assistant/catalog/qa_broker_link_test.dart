// QaBrokerLink en el chat: se muestra con el catálogo de la app, nunca va
// en el prompt (el modelo no lo ve), y el link sale del ticker y el bróker.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/broker_links/view/open_in_broker_links.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

import '../../../helpers/genui_test_helpers.dart';

void main() {
  test('registered only for display, never in the prompt', () {
    final display = AssistantCatalog.build(forDisplay: true);
    expect(display.items.map((i) => i.name), contains('QaBrokerLink'));
    final prompt = AssistantOpenAiService.systemPromptFor(
      AssistantCatalog.build(),
    );
    expect(prompt, isNot(contains('QaBrokerLink')));
  });

  testWidgets('renders "open in eToro" from ticker and broker', (tester) async {
    final catalog = AssistantCatalog.build(forDisplay: true);
    final item = catalog.items.firstWhere((i) => i.name == 'QaBrokerLink');
    final theme = ProviderContainer().read(themeDataLightProvider);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => item.widgetBuilder(
                    catalogContextFor(
                      buildContext: context,
                      catalog: catalog,
                      component: const {
                        'id': 'brokerLink',
                        'component': 'QaBrokerLink',
                        'ticker': 'aapl',
                        'broker': 'etoro',
                      },
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
    final links = tester.widget<OpenInBrokerLinks>(
      find.byType(OpenInBrokerLinks),
    );
    expect(links.ticker, 'AAPL');
    expect(find.text('broker_open_in'), findsOneWidget);
  });
}
