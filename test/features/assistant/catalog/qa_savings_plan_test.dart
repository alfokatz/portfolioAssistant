import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

Map<String, Object?> _retirement({double? monthly, double? income}) =>
    GoalProjectionBuilder.build(
      currentPortfolioValue: 10000,
      targetAmount: income == null ? 500000 : null,
      desiredMonthlyIncome: income,
      targetDate: DateTime(2046, 10, 9),
      label: 'Jubilación',
      monthlyContribution: monthly,
      asOf: _now,
    );

SavingsPlan _planOf(Map<String, Object?> built) => SavingsPlan.build(
  SavingsPlanInputs.fromJson((built['plan'] as Map)['inputs'])!,
);

Future<List<String>> _pump(
  WidgetTester tester, {
  required List<ToolCallRecord> calls,
  required String planId,
  String? focus,
}) async {
  final sent = <String>[];
  final catalog = AssistantCatalog.build();
  await tester.binding.setSurfaceSize(const Size(390, 3000));
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
                            if (focus != null) 'focus': focus,
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

String _answer(String planId, {String text = 'Armé tu plan.'}) =>
    '{"version":"v0.9","updateComponents":{"surfaceId":"s","components":'
    '[{"id":"root","component":"Column","children":["a","p"]},'
    '{"id":"a","component":"QaAnswerText","text":"$text"},'
    '{"id":"p","component":"QaSavingsPlan","planId":"$planId"}]}}';

void main() {
  testWidgets('savings focus: the monthly savings up top, the rest folded', (
    tester,
  ) async {
    final built = _retirement();
    final plan = _planOf(built);
    await _pump(tester, calls: [_call(built)], planId: '${built['plan_id']}');

    expect(find.text('Jubilación'), findsOneWidget);
    expect(find.text('Moderada'), findsOneWidget);
    expect(find.text('AHORRO MENSUAL SUGERIDO'), findsOneWidget);
    expect(
      find.text(
        '\$${_thousands(plan.requiredMonthly[PlanScenario.base]!.round())}',
      ),
      findsWidgets,
    );
    expect(find.text('Mercado flojo'), findsOneWidget);
    expect(find.textContaining('invertir serían \$2,042/mes'), findsOneWidget);
    expect(find.byType(QaSavingsPlanChart), findsNothing);
    expect(find.textContaining('no una garantía'), findsOneWidget);

    await tester.tap(find.text('Ver plan completo'));
    await tester.pumpAndSettle();
    expect(find.byType(QaSavingsPlanChart), findsOneWidget);
    expect(find.text('Acciones globales'), findsOneWidget);
    expect(find.text('Cómo cobrarías'), findsOneWidget);
    expect(find.text('De dividendos'), findsOneWidget);
    expect(find.text('Te jubilás 5 años antes'), findsOneWidget);
    expect(find.text('Ver menos'), findsOneWidget);
  });

  testWidgets('income focus: both ways to collect it, dividends chosen', (
    tester,
  ) async {
    final built = _retirement(income: 3000);
    final sent = await _pump(
      tester,
      calls: [_call(built)],
      planId: '${built['plan_id']}',
    );

    expect(find.text('Cómo cobrarías'), findsOneWidget);
    expect(
      find.text('Para cobrar \$3,000/mes necesitás juntar:'),
      findsOneWidget,
    );
    expect(find.text('De dividendos'), findsOneWidget);
    expect(find.text('Retirando el 4%'), findsOneWidget);
    expect(find.text('No tocás el capital'), findsOneWidget);
    expect(find.textContaining('Se consume en ~'), findsOneWidget);
    expect(find.text('Tu plan'), findsOneWidget);
    expect(find.text('PARA JUNTARLO, AHORRÁ'), findsOneWidget);

    await tester.ensureVisible(find.text('Usar retiro del 4%'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar retiro del 4%'));
    expect(sent, ['Rehacé el plan para cobrar retirando el 4% por año']);
  });

  testWidgets('growth focus: the slider moves the curve locally', (
    tester,
  ) async {
    final built = _retirement();
    await _pump(
      tester,
      calls: [_call(built)],
      planId: '${built['plan_id']}',
      focus: 'growth',
    );
    expect(find.byType(QaSavingsPlanChart), findsOneWidget);
    expect(find.text('Volver al plan'), findsNothing);
    expect(find.text('Llegás'), findsOneWidget);

    await tester.drag(find.byType(Slider), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(find.text('\$0/mes'), findsOneWidget);
    expect(find.textContaining('Faltan \$'), findsOneWidget);
    await tester.tap(find.text('Volver al plan'));
    await tester.pumpAndSettle();
    expect(find.text('Volver al plan'), findsNothing);
  });

  testWidgets('progress focus: how far along the goal is', (tester) async {
    final built = _retirement();
    await _pump(
      tester,
      calls: [_call(built)],
      planId: '${built['plan_id']}',
      focus: 'progress',
    );
    expect(find.text('HOY TENÉS'), findsOneWidget);
    expect(find.text('logrado'), findsOneWidget);
    expect(find.text('2%'), findsOneWidget);
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
    await tester.ensureVisible(find.text('Conservadora'));
    await tester.pumpAndSettle();
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
      final calls = [_call(built)];
      expect(
        AssistantGroundingCheck.check(_answer('${built['plan_id']}'), calls),
        isNull,
      );
      expect(AssistantGroundingCheck.check(_answer('plan-x'), calls), isNotNull);
    });

    test('a plan from an earlier turn is rejected: compute it again', () {
      final old = _call(_retirement());
      final id = '${old.result['plan_id']}';
      // El plan existe en la conversación, pero no se calculó en este turno.
      final stale = AssistantAnswerReview.check(
        _answer(id),
        TurnEvidence(calls: [old]),
      );
      expect(stale, isNotNull);
      expect(stale!.requiresTools, isTrue);
      expect(stale.message, contains('THIS turn'));

      expect(
        AssistantAnswerReview.check(
          _answer(id),
          TurnEvidence(calls: [old], turnCalls: [old]),
        ),
        isNull,
      );
    });

    test('the text explains with the plan numbers, never invented ones', () {
      final call = _call(_retirement(income: 3000));
      final id = '${call.result['plan_id']}';
      final evidence = TurnEvidence(calls: [call], turnCalls: [call]);

      const good =
          'Para cobrar 3.000 dólares por mes de dividendos necesitás '
          'unos 1,03 millones; retirando el 4% alcanzan 900 mil.';
      expect(
        AssistantAnswerReview.check(_answer(id, text: good), evidence),
        isNull,
      );
      expect(
        AssistantAnswerReview.postProcess(_answer(id, text: good), evidence),
        contains('900 mil'),
      );

      const bad = 'Con 4.700 dólares por mes llegás tranquilo.';
      final correction = AssistantAnswerReview.check(
        _answer(id, text: bad),
        evidence,
      );
      expect(correction, isNotNull);
      expect(correction!.requiresTools, isFalse);
      expect(
        AssistantAnswerReview.postProcess(_answer(id, text: bad), evidence),
        isNot(contains('4.700')),
      );
    });
  });
}

String _thousands(int v) =>
    v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
