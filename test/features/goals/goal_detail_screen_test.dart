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
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/savings_plan_edit_sheet.dart';
import 'package:portfolio_assistant/features/goals/view/goal_actions.dart';
import 'package:portfolio_assistant/features/goals/view/goal_detail_screen.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/features/assistant/view/porty_chat_sheet.dart';

class _Goals extends GoalsNotifier {
  _Goals(List<UserGoal> goals) : super(GoalsRepository(client: () => null)) {
    state = GoalsState(goals: goals, loaded: true);
  }
}

/// "Auto": 25 mil en 3 años, guardada hace 6 meses con VT y BND.
UserGoal goalFixture({
  String label = 'Auto',
  double outside = 0,
  Set<String> linked = const {'VT', 'BND'},
  List<GoalBuyPlanEntry> extra = const [],
}) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month - 6, now.day);
  return UserGoal(
    id: 'g1',
    label: label,
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
      buyPlan: [
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
        ...extra,
      ],
    ),
    status: GoalStatus.active,
    createdAt: start,
    linkedTickers: linked,
    externalSavings: outside,
  );
}

Future<void> pumpGoalDetail(
  WidgetTester tester, {
  required UserGoal goal,
  Map<String, double> holdings = const {},
  List<UserGoal> others = const [],
  ThemeData? theme,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        goalsProvider.overrideWith((ref) => _Goals([goal, ...others])),
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

    // Los de la pantalla (el de la barra es la píldora "Preguntale").
    final inBar = find.descendant(
      of: find.byType(PortyAskButton),
      matching: find.byType(PortyAvatar),
    );
    expect(inBar, findsOneWidget);
    final avatars = tester
        .widgetList<PortyAvatar>(find.byType(PortyAvatar))
        .where((a) => !tester.widgetList<PortyAvatar>(inBar).contains(a));
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

  testWidgets('a holding shared with another goal says how much of it is '
      'this goal\'s and why', (tester) async {
    final goal = goalFixture();
    // Otra meta con la mitad del monto, mismo plazo y mismo % en BND.
    final other = UserGoal(
      id: 'g2',
      label: 'Fiesta',
      type: GoalType.purchase,
      targetAmount: 12500,
      targetDate: goal.targetDate,
      snapshot: GoalPlanSnapshot(
        inputs: SavingsPlanInputs(
          targetAmount: 12500,
          months: 36,
          currentAmount: 0,
          // Un aporte mal cargado no le saca más parte.
          monthlyContribution: 20000,
          risk: RiskTolerance.aggressive,
          startDate: goal.snapshot.inputs.startDate,
        ),
        buyPlan: const [
          GoalBuyPlanEntry(
            ticker: 'BND',
            assetClassLabel: 'Bonos',
            pct: 15,
            monthlyAmount: 3000,
          ),
        ],
      ),
      status: GoalStatus.active,
      createdAt: goal.createdAt,
      linkedTickers: const {'BND'},
    );
    await pumpGoalDetail(
      tester,
      goal: goal,
      others: [other],
      holdings: {'BND': 900},
    );
    // A "Auto" (el doble de monto) le tocan 2/3 de los 900.
    expect(
      find.text(
        'goal_counts_shared'.tr(
          namedArgs: {
            'share': QaFormat.money(600),
            'total': QaFormat.money(900),
            'goals': 'Fiesta',
          },
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('goal_counts_shared_hint'.tr()),
      findsOneWidget,
    );
  });

  testWidgets('ahead of plan: Porty smiles', (tester) async {
    await pumpGoalDetail(tester, goal: goalFixture(outside: 9000));
    final first = tester.widget<PortyAvatar>(find.byType(PortyAvatar).first);
    expect(first.state, PortyAvatarState.answered);
  });

  testWidgets('a 0% instrument is not in the plan, and one the user took out '
      'of "Qué cuenta" says it does not count', (tester) async {
    await pumpGoalDetail(
      tester,
      goal: goalFixture(
        linked: const {'VT'},
        extra: const [
          GoalBuyPlanEntry(
            ticker: 'VOO',
            name: 'Vanguard S&P 500 ETF',
            assetClassLabel: 'Acciones globales',
            pct: 0,
            monthlyAmount: 0,
          ),
        ],
      ),
    );
    expect(find.text('VOO'), findsNothing);
    expect(find.text('goal_plan_not_counted'.tr()), findsOneWidget);
  });

  testWidgets('a long saved amount is shown whole', (tester) async {
    await pumpGoalDetail(tester, goal: goalFixture(outside: 12345));
    final text = tester.widget<Text>(find.text(QaFormat.money(12345)).first);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the options sheet: edit plan, mark achieved, delete', (
    tester,
  ) async {
    await pumpGoalDetail(tester, goal: goalFixture());
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.text('goal_edit_plan'.tr()), findsWidgets);
    expect(find.text('goal_mark_achieved'.tr()), findsOneWidget);
    expect(find.text('goal_delete'.tr()), findsOneWidget);

    // "Editar plan" abre el mismo editor que la card del chat.
    await tester.tap(find.text('goal_edit_plan_subtitle'.tr()));
    await tester.pumpAndSettle();
    expect(find.text('Nombre de la meta'), findsOneWidget);
  });

  test(
    'an edit that keeps the mix keeps the buy plan with the new amounts',
    () {
      final goal = goalFixture();
      // A 5 años de su inicio sigue con la cartera del perfil (con
      // acciones); a 3 años o menos pasaría a corto plazo.
      final later = DateTime(
        goal.targetDate.year + 2,
        goal.targetDate.month,
        goal.targetDate.day,
      );
      final draft =
          GoalActions.editedDraft(
            goal,
            SavingsPlanEdit(
              label: 'Auto usado',
              targetAmount: 30000,
              targetDate: later,
              currentAmount: 0,
              risk: goal.snapshot.inputs.risk,
            ),
          )!;
      expect(draft.label, 'Auto usado');
      expect([for (final e in draft.snapshot.buyPlan) e.ticker], ['VT', 'BND']);
      final monthly = draft.snapshot.plan.monthlyUsed;
      expect(
        draft.snapshot.buyPlan.first.monthlyAmount,
        (monthly * 0.85).round(),
      );

      // A un año pasa a corto plazo: van los instrumentos del plan nuevo.
      final short =
          GoalActions.editedDraft(
            goal,
            SavingsPlanEdit(
              label: 'Auto',
              targetAmount: 25000,
              targetDate: DateTime.now().add(const Duration(days: 365)),
              currentAmount: 0,
              risk: goal.snapshot.inputs.risk,
            ),
          )!;
      expect(
        [for (final e in short.snapshot.buyPlan) e.ticker],
        ['SGOV', 'VGSH'],
      );
    },
  );
}
