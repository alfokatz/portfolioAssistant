import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/catalog/assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_follow_up_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_goal_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/portfolio_qa_catalog.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
import 'package:portfolio_assistant/features/assistant/tools/advice_tools.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

import '../../../helpers/genui_test_helpers.dart';

/// "Quiero comprarme un auto de 25 mil en 3 años": la card es la propuesta
/// y el usuario la confirma para crear la meta.
final _built = {
  'status': 'ok',
  ...GoalProjectionBuilder.build(
    currentPortfolioValue: 10000,
    targetAmount: 25000,
    targetDate: DateTime(2029, 10, 11),
    label: 'Auto',
    isPurchase: true,
    asOf: DateTime(2026, 10, 11),
  ),
};

UserGoal _goalFrom(GoalDraft d) => UserGoal(
  id: 'goal-1',
  label: d.label,
  type: d.type,
  targetAmount: d.targetAmount,
  targetDate: d.targetDate,
  snapshot: d.snapshot,
  status: GoalStatus.active,
  createdAt: DateTime(2026, 10, 11),
  planKey: d.planKey,
);

Future<void> _pump(
  WidgetTester tester, {
  required List<GoalDraft> saved,
  List<UserGoal> existing = const [],
  GlobalKey? boundary,
}) async {
  final goals = [...existing];
  await tester.binding.setSurfaceSize(const Size(390, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final catalog = AssistantCatalog.build();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(extensions: const [CustomColors.light]),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: StatefulBuilder(
          builder:
              (context, setState) => QaGoalScope(
                savedFor:
                    (key) => goals.where((g) => g.planKey == key).firstOrNull,
                existingFor:
                    (label) => goals.where((g) => g.label == label).firstOrNull,
                onSave: (draft) async {
                  saved.add(draft);
                  final goal = _goalFrom(draft);
                  setState(() => goals.add(goal));
                  return goal;
                },
                onOpen: (_) {},
                child: QaEvidenceScope(
                  lookup:
                      (_) => ValueNotifier(
                        TurnEvidence(
                          calls: [
                            ToolCallRecord(
                              name: GetGoalProjectionTool.toolName,
                              args: const {},
                              result: _built,
                            ),
                          ],
                        ),
                      ),
                  child: QaFollowUpScope(
                    onFollowUp: (_) {},
                    child: Scaffold(
                      body: SingleChildScrollView(
                        child: RepaintBoundary(
                          key: boundary,
                          child: ColoredBox(
                            color: Colors.white,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Builder(
                                builder:
                                    (context) => qaSavingsPlanItem.widgetBuilder(
                                      catalogContextFor(
                                        buildContext: context,
                                        component: {
                                          'id': 'p',
                                          'component': 'QaSavingsPlan',
                                          'planId': _built['plan_id'],
                                          'focus': 'savings',
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
                ),
              ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the plan is a proposal: confirming creates the goal', (
    tester,
  ) async {
    final saved = <GoalDraft>[];
    await _pump(tester, saved: saved);

    // Corto plazo (3 años): liquidez y bonos cortos, con el monto de cada uno.
    expect(find.text('Corto plazo'), findsOneWidget);
    expect(find.text('Dónde invertir cada mes'), findsOneWidget);
    expect(find.textContaining('SGOV'), findsWidgets);
    expect(find.textContaining('VGSH'), findsWidgets);

    final confirm = find.text('Confirmar y crear meta');
    expect(confirm, findsOneWidget);
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(saved.single.label, 'Auto');
    expect(saved.single.targetAmount, 25000);
    expect(find.text('Meta creada en Metas'), findsOneWidget);
    expect(find.text('Confirmar y crear meta'), findsNothing);
  });

  testWidgets('a goal with the same name is updated, not duplicated', (
    tester,
  ) async {
    final draft = GoalDraft.fromToolResult(_built)!;
    final old = _goalFrom(
      GoalDraft(
        label: draft.label,
        type: draft.type,
        targetAmount: 20000,
        targetDate: draft.targetDate,
        snapshot: draft.snapshot,
        planKey: 'plan-old',
      ),
    );
    await _pump(tester, saved: [], existing: [old]);
    expect(find.text('Confirmar y actualizar meta'), findsOneWidget);
  });
}
