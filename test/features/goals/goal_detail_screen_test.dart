import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/goals/data/goals_repository.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_progress.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/features/goals/view/goal_detail_screen.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

class _Goals extends GoalsNotifier {
  _Goals(List<UserGoal> goals) : super(GoalsRepository(client: () => null)) {
    state = GoalsState(goals: goals, loaded: true);
  }
}

/// "Auto": 25 mil en 3 años, guardada hace 6 meses con VT y BND.
UserGoal goalFixture({double outside = 0}) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month - 6, now.day);
  return UserGoal(
    id: 'g1',
    label: 'Auto',
    type: GoalType.purchase,
    targetAmount: 25000,
    targetDate: DateTime(start.year + 3, start.month, start.day),
    snapshot: GoalPlanSnapshot(
      inputs: SavingsPlanInputs(
        targetAmount: 25000,
        months: 36,
        currentAmount: 0,
        risk: RiskTolerance.aggressive,
        startDate: start,
      ),
      buyPlan: const [
        GoalBuyPlanEntry(
          ticker: 'VT',
          name: 'Vanguard Total World Stock ETF',
          assetClassLabel: 'Acciones globales',
          pct: 85,
          monthlyAmount: 553,
        ),
        GoalBuyPlanEntry(
          ticker: 'BND',
          name: 'Vanguard Total Bond Market ETF',
          assetClassLabel: 'Bonos',
          pct: 15,
          monthlyAmount: 98,
        ),
      ],
    ),
    status: GoalStatus.active,
    createdAt: start,
    linkedTickers: const {'VT', 'BND'},
    externalSavings: outside,
  );
}

Future<void> pumpGoalDetail(
  WidgetTester tester, {
  required UserGoal goal,
  Map<String, double> holdings = const {},
  ThemeData? theme,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        goalsProvider.overrideWith((ref) => _Goals([goal])),
        goalHoldingsProvider.overrideWithValue(holdings),
      ],
      child: RepaintBoundary(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme ?? ProviderContainer().read(themeDataLightProvider),
          home: const GoalDetailScreen(goalId: 'g1'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Carga los textos en español (el plural de "meses" los necesita).
void loadSpanish() => Localization.load(
  const Locale('es', 'ES'),
  translations: Translations(
    jsonDecode(File('assets/translations/es-ES.json').readAsStringSync())
        as Map<String, dynamic>,
  ),
  ignorePluralRules: false,
);

void main() {
  setUpAll(loadSpanish);

  test('Porty looks like the goal is going', () {
    expect(goalMood(GoalProgressStatus.justStarted), PortyAvatarState.idle);
    expect(goalMood(GoalProgressStatus.onTrack), PortyAvatarState.idle);
    expect(goalMood(GoalProgressStatus.ahead), PortyAvatarState.answered);
    expect(goalMood(GoalProgressStatus.achieved), PortyAvatarState.answered);
    expect(goalMood(GoalProgressStatus.behind), PortyAvatarState.concerned);
    expect(goalMood(GoalProgressStatus.overdue), PortyAvatarState.concerned);
  });

  testWidgets('behind plan: Porty is concerned; held investments open '
      'their detail, the rest do not', (tester) async {
    await pumpGoalDetail(tester, goal: goalFixture(), holdings: {'VT': 300});

    final avatars = tester.widgetList<PortyAvatar>(find.byType(PortyAvatar));
    expect(avatars.first.state, PortyAvatarState.concerned);
    // "Preguntarle a Porty" lleva a Porty, no un ícono de chat.
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);
    expect(avatars.length, 2);

    // Logos en el plan y en lo que cuenta.
    expect(find.byType(QaTickerAvatar), findsNWidgets(4));
    // Solo VT (que tiene) lleva chevron; el último es el de Porty.
    expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(2));
    expect(find.text('goal_counts_not_held'.tr()), findsOneWidget);
  });

  testWidgets('ahead of plan: Porty smiles', (tester) async {
    await pumpGoalDetail(tester, goal: goalFixture(outside: 9000));
    final first = tester.widget<PortyAvatar>(find.byType(PortyAvatar).first);
    expect(first.state, PortyAvatarState.answered);
  });
}
