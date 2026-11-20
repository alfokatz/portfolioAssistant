import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/allocation_plan_card_data.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_grounding_check.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/shared/widgets/genui_error_card.dart';

import '../../../helpers/genui_test_helpers.dart';

ToolCallRecord _plan({bool withContribution = false, String status = 'ok'}) =>
    ToolCallRecord(
      name: 'get_allocation_plan',
      args: {if (withContribution) 'contribution_usd': 500},
      result: {
        'status': status,
        'drift_threshold': 5.0,
        'portfolio_value_usd': 10000.0,
        'off_plan': ['AAPL', 'VOO'],
        'rows': [
          {
            'ticker': 'VOO',
            'current_pct': 34.6,
            'target_pct': 43.0,
            'drift_pts': -8.4,
          },
          {
            'ticker': 'GOOGL',
            'current_pct': 22.0,
            'target_pct': 25.0,
            'drift_pts': -3.0,
          },
          {
            'ticker': 'AAPL',
            'current_pct': 25.7,
            'target_pct': 11.0,
            'drift_pts': 14.7,
          },
          {
            'ticker': 'DUOL',
            'current_pct': 4.4,
            'target_pct': 0.0,
            'drift_pts': 4.4,
          },
        ],
        if (withContribution)
          'contribution': {
            'amount_usd': 500.0,
            'split': [
              {'ticker': 'VOO', 'amount_usd': 350.0},
              {'ticker': 'GOOGL', 'amount_usd': 150.0},
            ],
          },
      },
    );

Future<void> _pump(WidgetTester tester, List<ToolCallRecord> calls) async {
  final catalog = AssistantCatalog.build();
  final item = catalog.items.firstWhere((i) => i.name == 'QaAllocationPlan');
  await tester.binding.setSurfaceSize(const Size(390, 2000));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [CustomColors.light]),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: QaEvidenceScope(
          lookup: (_) => ValueNotifier(TurnEvidence(calls: calls)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Builder(
                builder:
                    (context) => item.widgetBuilder(
                      catalogContextFor(
                        buildContext: context,
                        component: {'id': 'p', 'component': 'QaAllocationPlan'},
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
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  expect(find.byType(GenUiErrorCard), findsNothing);
}

void main() {
  testWidgets('plan vs. today comes from the tool, with each status', (
    tester,
  ) async {
    await _pump(tester, [_plan()]);
    expect(find.text('Tu plan de cartera'), findsOneWidget);
    expect(find.text('2 fuera'), findsOneWidget);
    expect(find.text('Plan 43% · Hoy 35%'), findsOneWidget);
    expect(find.text('+15 pts'), findsOneWidget);
    expect(find.text('−8 pts'), findsOneWidget);
    expect(find.text('En plan'), findsOneWidget); // GOOGL
    expect(find.text('Fuera del plan'), findsOneWidget); // DUOL
    expect(find.textContaining('Si sumás'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with a contribution: amount per ticker and where it lands', (
    tester,
  ) async {
    await _pump(tester, [_plan(withContribution: true)]);
    expect(find.text('Si sumás \$500'), findsOneWidget);
    expect(find.text('\$350'), findsOneWidget);
    // VOO: (3460 + 350) / 10500 = 36%.
    expect(find.text('Quedaría en 36% (plan 43%)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without an ok result the card shows nothing', (tester) async {
    await _pump(tester, [_plan(status: 'failed')]);
    expect(find.text('Tu plan de cartera'), findsNothing);
  });

  test('backing numbers include the drawn values', () {
    final d =
        AllocationPlanCardData.fromJson(
          _plan(withContribution: true).result.cast<String, dynamic>(),
        )!;
    expect(d.backingNumbers, containsAll([43.0, 34.6, 14.7, 500.0, 350.0]));
    expect(d.offPlan.map((r) => r.ticker), ['VOO', 'AAPL']);
  });

  test('grounding: the card needs get_allocation_plan', () {
    const answer =
        '{"updateComponents":{"components":['
        '{"id":"root","component":"Column","children":["p"]},'
        '{"id":"p","component":"QaAllocationPlan"}]}}';
    expect(AssistantGroundingCheck.check(answer, const []), isNotNull);
    expect(AssistantGroundingCheck.check(answer, [_plan()]), isNull);
  });

  test('the widget is in the assistant catalog', () {
    expect(AssistantCatalog.widgetNames, contains('QaAllocationPlan'));
  });
}
