import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_follow_up_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog.dart';
import 'package:portfolio_assistant/features/assistant/data/market/dividend_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/buy_plan_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/assistant/tools/advice_tools.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_answer_review.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

import '../../../helpers/genui_test_helpers.dart';
import '../fakes/assistant_fakes.dart';

ToolCallRecord _buyCall() {
  final base = GoalProjectionBuilder.build(
    currentPortfolioValue: 0,
    desiredMonthlyIncome: 3000,
    targetDate: DateTime(2051, 10, 9),
    asOf: DateTime(2026, 10, 9),
  );
  final result = BuyPlanBuilder.build(
    base: base,
    picks: const [
      BuyPlanPick('SCHD', PlanAssetClass.equities),
      BuyPlanPick('KO', PlanAssetClass.equities),
      BuyPlanPick('BND', PlanAssetClass.bonds),
    ],
    info: {
      'SCHD': DividendFetcher.parse(
        dividendQuoteSummary(name: 'Schwab ETF', yieldFraction: 0.036),
      ),
      'KO': DividendFetcher.parse(
        dividendQuoteSummary(
          name: 'Coca-Cola',
          etf: false,
          yieldFraction: 0.029,
        ),
      ),
      'BND': DividendFetcher.parse(
        dividendQuoteSummary(name: 'Bond ETF', yieldFraction: 0.038),
      ),
    },
  );
  return ToolCallRecord(
    name: GetMonthlyBuyPlanTool.toolName,
    args: const {},
    result: result,
  );
}

String _answer(String id, {String text = 'Armé tu compra.'}) =>
    '{"version":"v0.9","updateComponents":{"surfaceId":"s","components":'
    '[{"id":"root","component":"Column","children":["a","b"]},'
    '{"id":"a","component":"QaAnswerText","text":"$text"},'
    '{"id":"b","component":"QaBuyPlan","buyPlanId":"$id"}]}}';

void main() {
  testWidgets('the buy plan shows what to buy, how much and its yield', (
    tester,
  ) async {
    final call = _buyCall();
    final sent = <String>[];
    final catalog = AssistantCatalog.build();
    await tester.binding.setSurfaceSize(const Size(390, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [CustomColors.light]),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: QaEvidenceScope(
            lookup: (_) => ValueNotifier(TurnEvidence(calls: [call])),
            child: QaFollowUpScope(
              onFollowUp: sent.add,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Builder(
                    builder:
                        (context) => qaBuyPlanItem.widgetBuilder(
                          catalogContextFor(
                            buildContext: context,
                            component: {
                              'id': 'b',
                              'component': 'QaBuyPlan',
                              'buyPlanId': '${call.result['buy_plan_id']}',
                            },
                            catalog: catalog,
                            surfaceId: 's1',
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('Tu compra mensual'), findsOneWidget);
    // El avatar sin logo muestra las iniciales: el ticker puede repetirse.
    for (final t in ['SCHD', 'KO', 'BND']) {
      expect(find.text(t), findsWidgets);
    }
    expect(find.text('ETF'), findsNWidgets(2));
    expect(find.text('Acción'), findsOneWidget);
    expect(find.textContaining('15% · rinde 2,9%'), findsOneWidget);
    expect(find.text('Con estos rendimientos'), findsOneWidget);
    expect(find.textContaining('el plan suponía 3,5%'), findsOneWidget);
    expect(find.text('Cobrarías por mes'), findsOneWidget);
    expect(find.textContaining('no una recomendación'), findsOneWidget);

    await tester.ensureVisible(find.text('Ver plan actualizado'));
    await tester.tap(find.text('Ver plan actualizado'));
    expect(sent, ['Mostrame el plan con estos rendimientos']);
  });

  test(
    'review: the buy plan must be from this turn; text uses its numbers',
    () {
      final call = _buyCall();
      final id = '${call.result['buy_plan_id']}';
      expect(
        AssistantAnswerReview.check(_answer(id), TurnEvidence(calls: [call])),
        isNotNull,
      );
      final evidence = TurnEvidence(calls: [call], turnCalls: [call]);
      expect(AssistantAnswerReview.check(_answer(id), evidence), isNull);

      final monthly = call.result['monthly_amount'];
      final good =
          'Cada mes invertís $monthly dólares, con un tope de 15% por acción.';
      expect(
        AssistantAnswerReview.check(_answer(id, text: good), evidence),
        isNull,
      );
      expect(
        AssistantAnswerReview.check(
          _answer(id, text: 'SCHD rinde 12,3% por año.'),
          evidence,
        ),
        isNotNull,
      );
    },
  );
}
