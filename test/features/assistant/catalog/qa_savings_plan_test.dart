import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_follow_up_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_savings_plan_chart.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/savings_plan_widgets.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/assistant/tools/advice_tools.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_answer_review.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_grounding_check.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

import '../../../helpers/genui_test_helpers.dart';

final _now = DateTime(2026, 10, 9);

ToolCallRecord _call(Map<String, Object?> built) => ToolCallRecord(
  name: GetGoalProjectionTool.toolName,
  args: const {},
  result: {'status': 'ok', ...built},
);

Map<String, Object?> _retirement({
  double? monthly,
  RiskTolerance? risk,
  DateTime? date,
}) => GoalProjectionBuilder.build(
  currentPortfolioValue: 10000,
  targetAmount: 500000,
  targetDate: date ?? DateTime(2046, 10, 9),
  label: 'Jubilación',
  monthlyContribution: monthly,
  statedRisk: risk,
  asOf: _now,
);

Future<List<String>> _pump(
  WidgetTester tester, {
  required List<ToolCallRecord> calls,
  required String planId,
}) async {
  final sent = <String>[];
  final catalog = AssistantCatalog.build();
  await tester.binding.setSurfaceSize(const Size(390, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [CustomColors.light]),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: QaEvidenceScope(
          lookup: (_) => ValueNotifier(TurnEvidence(calls: calls)),
          child: QaFollowUpScope(
            onFollowUp: sent.add,
            child: Scaffold(
              body: SingleChildScrollView(
                child: Builder(
                  builder:
                      (context) => qaSavingsPlanItem.widgetBuilder(
                        catalogContextFor(
                          buildContext: context,
                          component: {
                            'id': 'p',
                            'component': 'QaSavingsPlan',
                            'planId': planId,
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
  return sent;
}

void main() {
  testWidgets(
    'a retirement plan shows savings, growth, allocation and income',
    (tester) async {
      final built = _retirement();
      final plan = SavingsPlan.build(
        SavingsPlanInputs.fromJson((built['plan'] as Map)['inputs'])!,
      );
      await _pump(tester, calls: [_call(built)], planId: '${built['plan_id']}');

      expect(find.text('Jubilación'), findsOneWidget);
      expect(find.text('Moderada'), findsOneWidget);
      expect(
        find.text(
          '\$${_thousands(plan.requiredMonthly[PlanScenario.base]!.round())}',
        ),
        findsWidgets,
      );
      expect(
        find.textContaining('invertir serían \$2,042/mes'),
        findsOneWidget,
      );
      expect(find.byType(QaSavingsPlanChart), findsOneWidget);
      expect(find.text('Acciones globales'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('Al jubilarte'), findsOneWidget);
      expect(find.text('Te jubilás 5 años antes'), findsOneWidget);
      expect(find.textContaining('perfil de inversor'), findsWidgets);
      expect(find.textContaining('no una garantía'), findsOneWidget);
    },
  );

  testWidgets('the slider moves the projection without asking the model', (
    tester,
  ) async {
    final built = _retirement();
    await _pump(tester, calls: [_call(built)], planId: '${built['plan_id']}');
    expect(find.text('Volver al plan'), findsNothing);
    expect(find.text('Llegás'), findsOneWidget);

    await tester.drag(find.byType(Slider), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(find.text('\$0/mes'), findsOneWidget);
    expect(find.textContaining('Faltan'), findsOneWidget);
    await tester.tap(find.text('Volver al plan'));
    await tester.pumpAndSettle();
    expect(find.text('Volver al plan'), findsNothing);
  });

  testWidgets('a short contribution is flagged', (tester) async {
    final built = _retirement(monthly: 300);
    await _pump(tester, calls: [_call(built)], planId: '${built['plan_id']}');
    expect(find.text('Falta ritmo'), findsOneWidget);
    expect(find.textContaining('Hoy aportás \$300/mes'), findsOneWidget);
  });

  testWidgets('risk chips ask for the plan with another allocation', (
    tester,
  ) async {
    final built = _retirement();
    final sent = await _pump(
      tester,
      calls: [_call(built)],
      planId: '${built['plan_id']}',
    );
    await tester.tap(find.text('Conservadora'));
    expect(sent, ['Rehacé el plan con una cartera conservadora']);
  });

  testWidgets('an unknown plan id draws nothing', (tester) async {
    final built = _retirement();
    await _pump(tester, calls: [_call(built)], planId: 'plan-nope');
    expect(find.byType(QaSavingsPlanCard), findsNothing);
  });

  group('review', () {
    test('grounding needs the exact plan id', () {
      final built = _retirement();
      String answer(String id) =>
          '{"version":"v0.9","updateComponents":{"surfaceId":"s","components":'
          '[{"id":"root","component":"Column","children":["p"]},'
          '{"id":"p","component":"QaSavingsPlan","planId":"$id"}]}}';
      final calls = [_call(built)];
      expect(
        AssistantGroundingCheck.check(answer('${built['plan_id']}'), calls),
        isNull,
      );
      expect(AssistantGroundingCheck.check(answer('plan-x'), calls), isNotNull);
    });

    test('the intro does not repeat the card numbers', () {
      final built = _retirement();
      final plan = SavingsPlan.build(
        SavingsPlanInputs.fromJson((built['plan'] as Map)['inputs'])!,
      );
      final monthly = plan.requiredMonthly[PlanScenario.base]!.round();
      final line =
          '{"version":"v0.9","updateComponents":{"surfaceId":"s","components":'
          '[{"id":"root","component":"Column","children":["a","p"]},'
          '{"id":"a","component":"QaAnswerText","text":"Necesitás ahorrar '
          '\$$monthly por mes. Gran parte la hacen los intereses."},'
          '{"id":"p","component":"QaSavingsPlan","planId":"${built['plan_id']}"}]}}';
      final out = AssistantAnswerReview.postProcess(
        line,
        TurnEvidence(calls: [_call(built)]),
      );
      expect(out, contains('Gran parte la hacen los intereses.'));
      expect(out, isNot(contains('Necesitás ahorrar')));
    });
  });
}

String _thousands(int v) =>
    v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
