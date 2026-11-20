import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/savings_plan_edit_sheet.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_calculator.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_currency.dart';
import 'package:portfolio_assistant/features/goals/data/goals_repository.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_replan.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/features/goals/view/goal_actions.dart';

import 'goal_detail_screen_test.dart' show loadSpanish, pumpGoalDetail;

/// Repo en memoria con lo que importa acá: plan, inversiones asignadas y
/// ahorros fuera de la app.
class _Repo extends GoalsRepository {
  _Repo(List<UserGoal> initial) : super(client: () => null) {
    goals.addAll(initial);
  }

  final goals = <UserGoal>[];
  int planUpdates = 0;

  @override
  Future<List<UserGoal>> list() async => [...goals];

  UserGoal _copy(
    UserGoal g, {
    GoalDraft? draft,
    Set<String>? linked,
    double? external,
    DisplayCurrency? currency,
  }) => UserGoal(
    id: g.id,
    label: draft?.label ?? g.label,
    type: draft?.type ?? g.type,
    targetAmount: draft?.targetAmount ?? g.targetAmount,
    targetDate: draft?.targetDate ?? g.targetDate,
    snapshot: draft?.snapshot ?? g.snapshot,
    status: g.status,
    createdAt: g.createdAt,
    linkedTickers: linked ?? g.linkedTickers,
    externalSavings: external ?? g.externalSavings,
    currency: currency ?? g.currency,
  );

  void _replace(String id, UserGoal Function(UserGoal) f) {
    final i = goals.indexWhere((g) => g.id == id);
    goals[i] = f(goals[i]);
  }

  @override
  Future<void> updatePlan(
    String id,
    GoalDraft draft, {
    Set<String>? linkedTickers,
    DisplayCurrency? currency,
  }) async {
    planUpdates++;
    _replace(
      id,
      (g) => _copy(g, draft: draft, linked: linkedTickers, currency: currency),
    );
  }

  @override
  Future<void> setLinkedTickers(String id, Set<String> tickers) async =>
      _replace(id, (g) => _copy(g, linked: tickers));

  @override
  Future<void> setExternalSavings(String id, double amount) async =>
      _replace(id, (g) => _copy(g, external: amount));
}

final _today = DateTime(2026, 10, 12);

/// "Viaje a Japón": 18 mil para febrero de 2028, a corto plazo (SGOV/VGSH),
/// guardada hace 4 meses sin nada juntado.
UserGoal _trip({
  String id = 'trip',
  Set<String> linked = const {'SGOV', 'VGSH'},
  double external = 0,
  DisplayCurrency currency = DisplayCurrency.usd,
}) => UserGoal(
  id: id,
  label: 'Viaje a Japón',
  type: GoalType.purchase,
  targetAmount: 18000,
  targetDate: DateTime(2028, 2, 12),
  snapshot: GoalPlanSnapshot(
    inputs: SavingsPlanInputs(
      targetAmount: 18000,
      months: 20,
      currentAmount: 0,
      risk: RiskTolerance.conservative,
      startDate: DateTime(2026, 6, 12),
      shortTerm: true,
    ),
    buyPlan: const [
      GoalBuyPlanEntry(
        ticker: 'SGOV',
        assetClassLabel: 'Liquidez',
        pct: 70,
        monthlyAmount: 630,
      ),
      GoalBuyPlanEntry(
        ticker: 'VGSH',
        assetClassLabel: 'Bonos',
        pct: 30,
        monthlyAmount: 270,
      ),
    ],
  ),
  status: GoalStatus.active,
  createdAt: DateTime(2026, 6, 12),
  linkedTickers: linked,
  externalSavings: external,
  currency: currency,
);

GoalsNotifier _notifier(_Repo repo, Map<String, double> holdings) =>
    GoalsNotifier(repo, holdings: () => holdings, clock: () => _today);

void main() {
  group('moneda de la meta', () {
    test('una fila sin la columna (base sin migrar) queda en dólares; con '
        'la columna, en su moneda', () {
      final row = {
        'id': 'g',
        'label': 'Auto',
        'target_amount': 1000000,
        'target_date': '2028-01-01',
        'created_at': '2026-10-01T00:00:00Z',
        'plan': _trip().snapshot.toJson(),
      };
      expect(UserGoal.fromRow(row)!.currency, DisplayCurrency.usd);
      expect(
        UserGoal.fromRow({...row, 'currency': 'UYU'})!.currency,
        DisplayCurrency.uyu,
      );
    });

    test('las inversiones (en dólares) se pasan a la moneda de la meta con '
        'el tipo de cambio de hoy; lo de afuera ya está en su moneda', () {
      final goal = _trip(
        currency: DisplayCurrency.uyu,
        external: 5000,
      ).withFx(40);
      expect(goal.linkedValues({'SGOV': 1000}), {'SGOV': 40000});
      expect(goal.savedWith({'SGOV': 1000}), 45000);
      // En dólares, nada cambia.
      expect(_trip().savedWith({'SGOV': 1000}), 1000);
    });

    test('sin tipo de cambio no cuenta las inversiones y lo dice', () {
      final goal = _trip(currency: DisplayCurrency.uyu, external: 5000);
      expect(goal.fxMissing, isTrue);
      expect(goal.linkedValues({'SGOV': 1000}), isEmpty);
      expect(goal.savedWith({'SGOV': 1000}), 5000);
      expect(_trip().fxMissing, isFalse);
    });

    test('al cargar, cada meta en otra moneda trae su tipo de cambio y el '
        'plan parte de sus inversiones convertidas', () async {
      final repo = _Repo([_trip(currency: DisplayCurrency.uyu)]);
      final goals = GoalsNotifier(
        repo,
        holdings: () => {'SGOV': 1000},
        clock: () => _today,
        loadFxRate: (c) async => c == DisplayCurrency.uyu ? 40 : null,
      );
      await goals.load();
      expect(goals.state.goals.single.fxRate, 40);
      await goals.setExternalSavings('trip', 2000);
      // 1000 dólares × 40 + 2000 pesos de afuera.
      expect(repo.goals.single.snapshot.inputs.currentAmount, 42000);
      expect(repo.goals.single.currency, DisplayCurrency.uyu);
    });

    test(
      'sin tipo de cambio el plan no se rehace con un número a medias',
      () async {
        final repo = _Repo([_trip(currency: DisplayCurrency.uyu)]);
        final goals = GoalsNotifier(
          repo,
          holdings: () => {'SGOV': 1000},
          clock: () => _today,
          loadFxRate: (_) async => null,
        );
        await goals.load();
        await goals.setExternalSavings('trip', 2000);
        expect(repo.planUpdates, 0);
      },
    );
  });

  test('outside savings become the plan starting point (plus the counted '
      'holdings) and the monthly amount is recalculated from today', () async {
    final repo = _Repo([_trip()]);
    final goals = _notifier(repo, {'SGOV': 1000});
    await goals.load();
    // Lo que haría falta desde hoy sin contar nada de lo que ya tiene.
    final fromScratch =
        GoalReplan.draft(
          goals.state.byId('trip')!,
          startDate: _today,
        )!.snapshot.plan.monthlyUsed;

    await goals.setExternalSavings('trip', 2500);

    final trip = goals.state.byId('trip')!;
    expect(trip.externalSavings, 2500);
    final inputs = trip.snapshot.inputs;
    expect(inputs.currentAmount, 3500);
    expect(inputs.startDate, _today);
    expect(inputs.months, 16);
    expect(trip.snapshot.plan.monthlyUsed, lessThan(fromScratch));
    // La compra mensual sigue, con los montos nuevos.
    final monthly = trip.snapshot.plan.monthlyUsed;
    expect([for (final e in trip.snapshot.buyPlan) e.ticker], ['SGOV', 'VGSH']);
    expect(trip.snapshot.buyPlan.first.monthlyAmount, (monthly * 0.7).round());
  });

  test('the same outside amount again does not rewrite the plan', () async {
    final repo = _Repo([_trip()]);
    final goals = _notifier(repo, const {});
    await goals.load();
    await goals.setExternalSavings('trip', 0);
    expect(repo.planUpdates, 0);
  });

  test('counting a stock the user already holds adds its share to the '
      'total and recalculates the monthly amount, also for the goal it is '
      'shared with', () async {
    final car = _trip(id: 'car', linked: const {'AAPL'});
    final repo = _Repo([_trip(), car]);
    final goals = _notifier(repo, {'AAPL': 4000});
    await goals.load();
    final fromScratch =
        GoalReplan.draft(
          goals.state.byId('trip')!,
          startDate: _today,
        )!.snapshot.plan.monthlyUsed;

    await goals.setLinkedTickers('trip', {'SGOV', 'VGSH', 'AAPL'});

    // Ninguno de los dos planes compra AAPL: se reparte en partes iguales.
    final trip = goals.state.byId('trip')!;
    expect(trip.snapshot.inputs.currentAmount, 2000);
    expect(trip.snapshot.plan.monthlyUsed, lessThan(fromScratch));
    expect(goals.state.byId('car')!.linkedTickers, {'AAPL'});
    expect(goals.state.byId('car')!.snapshot.inputs.currentAmount, 2000);

    // Sacarla: al auto le vuelve a tocar todo.
    await goals.setLinkedTickers('trip', {'SGOV', 'VGSH'});
    expect(goals.state.byId('trip')!.snapshot.inputs.currentAmount, 0);
    expect(goals.state.byId('car')!.snapshot.inputs.currentAmount, 4000);
  });

  test('a stock the user does not hold yet changes nothing', () async {
    final repo = _Repo([_trip()]);
    final goals = _notifier(repo, const {});
    await goals.load();
    await goals.setLinkedTickers('trip', {'SGOV', 'VGSH', 'VOO'});
    expect(repo.planUpdates, 0);
  });

  test('the plan editor: "lo que ya tenés" are the outside savings, and the '
      'plan adds the counted holdings to them', () async {
    final repo = _Repo([_trip()]);
    final goals = _notifier(repo, {'SGOV': 1000});
    await goals.load();
    final trip = goals.state.byId('trip')!;
    final draft =
        GoalActions.editedDraft(
          trip,
          SavingsPlanEdit(
            label: trip.label,
            targetAmount: trip.targetAmount,
            targetDate: trip.targetDate,
            currentAmount: 2500,
            risk: trip.snapshot.inputs.risk,
          ),
          holdings: {'SGOV': 1000},
          now: _today,
        )!;
    expect(draft.snapshot.inputs.currentAmount, 3500);
    expect(draft.snapshot.inputs.startDate, _today);

    await goals.updatePlan('trip', draft, externalSavings: 2500);
    final saved = goals.state.byId('trip')!;
    expect(saved.externalSavings, 2500);
    expect(saved.snapshot.inputs.currentAmount, 3500);
  });

  group('editor', () {
    setUpAll(loadSpanish);

    testWidgets('"Editar plan" opens with the outside savings filled in and '
        'says the counted holdings add up on their own', (tester) async {
      await pumpGoalDetail(
        tester,
        // El detalle de los tests busca la meta 'g1'.
        goal: _trip(id: 'g1', external: 2500),
        holdings: {'SGOV': 1000},
      );
      await tester.tap(find.text('goal_edit_plan'.tr()).last);
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.ancestor(
          of: find.text('goal_outside_title'.tr()),
          matching: find.byType(TextField),
        ),
      );
      expect(field.controller!.text, '2500');
      expect(
        find.text(
          'goal_edit_outside_helper_invested'.tr(
            namedArgs: {'amount': QaFormat.money(1000)},
          ),
        ),
        findsOneWidget,
      );
    });
  });
}
