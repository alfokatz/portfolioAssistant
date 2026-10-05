import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_follow_up_scope.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/shared/widgets/genui_error_card.dart';

import '../../../helpers/genui_test_helpers.dart';

ToolCallRecord _holdings(Map<String, Object?> result, {String status = 'ok'}) =>
    ToolCallRecord(
      name: 'get_etf_holdings',
      args: const {
        'tickers': ['XLF'],
      },
      result: {'status': status, ...result},
    );

final _xlf = _holdings({
  'etfs': {
    'XLF': {
      'fund_name': 'Financial Select Sector SPDR Fund',
      'category': 'Financial',
      'expense_ratio_pct': 0.08,
      'total_assets_usd': 49500000000,
      'top_holdings': [
        {
          'symbol': 'BRK-B',
          'name': 'Berkshire Hathaway Inc Class B',
          'weight_pct': 12.05,
        },
        {'symbol': 'JPM', 'name': 'JPMorgan Chase & Co', 'weight_pct': 10.21},
        {'symbol': 'V', 'name': 'Visa Inc Class A', 'weight_pct': 7.54},
      ],
      'top_holdings_weight_pct': 29.8,
      'sectors': [
        {'sector': 'Finanzas', 'weight_pct': 87.12},
        {'sector': 'Bienes raíces', 'weight_pct': 1.23},
      ],
    },
  },
});

Future<void> _pump(
  WidgetTester tester, {
  required List<ToolCallRecord> calls,
  String ticker = 'XLF',
  ValueChanged<String>? onFollowUp,
}) async {
  final catalog = AssistantCatalog.build();
  final item = catalog.items.firstWhere((i) => i.name == 'QaEtfHoldings');
  await tester.binding.setSurfaceSize(const Size(390, 2000));
  Widget body = Scaffold(
    body: SingleChildScrollView(
      child: Builder(
        builder:
            (context) => item.widgetBuilder(
              catalogContextFor(
                buildContext: context,
                component: {
                  'id': 'h',
                  'component': 'QaEtfHoldings',
                  'ticker': ticker,
                },
                catalog: catalog,
                surfaceId: 's1',
              ),
            ),
      ),
    ),
  );
  if (onFollowUp != null) {
    body = QaFollowUpScope(onFollowUp: onFollowUp, child: body);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [CustomColors.light]),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: QaEvidenceScope(
          lookup: (_) => ValueNotifier(TurnEvidence(calls: calls)),
          child: body,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  expect(find.byType(GenUiErrorCard), findsNothing);
}

void main() {
  testWidgets('holdings, weights, sectors and cost come from the tool, '
      'not from the model', (tester) async {
    await _pump(tester, calls: [_xlf]);

    expect(find.text('Financial Select Sector SPDR Fund'), findsOneWidget);
    expect(find.text('Berkshire Hathaway Inc Class B'), findsOneWidget);
    expect(find.text('12.1%'), findsOneWidget);
    expect(find.text('JPM'), findsOneWidget);
    expect(find.text('0.08%'), findsOneWidget);
    expect(find.text('29.8%'), findsOneWidget);
    expect(find.text('Finanzas 87.1%'), findsOneWidget);
    // Que quede claro que no es la cartera completa.
    expect(find.textContaining('no su cartera completa'), findsOneWidget);
  });

  testWidgets('tapping a holding asks about that ticker', (tester) async {
    String? asked;
    await _pump(tester, calls: [_xlf], onFollowUp: (q) => asked = q);

    await tester.tap(find.text('JPMorgan Chase & Co'));
    await tester.pump();
    expect(asked, '¿Cómo viene JPM?');
  });

  testWidgets('without an ok result for the ticker the card shows nothing',
      (tester) async {
    await _pump(
      tester,
      calls: [
        _holdings({'etfs': <String, Object?>{}}, status: 'failed'),
      ],
    );
    expect(find.text('Principales posiciones'.toUpperCase()), findsNothing);

    await _pump(tester, calls: [_xlf], ticker: 'VOO');
    expect(find.text('Berkshire Hathaway Inc Class B'), findsNothing);
  });

  test('the widget is in the assistant catalog', () {
    expect(AssistantCatalog.widgetNames, contains('QaEtfHoldings'));
    expect(
      AssistantCatalog.build().items.map((i) => i.name),
      contains('QaEtfHoldings'),
    );
  });
}
