import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/goals/data/goals_repository.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_replan.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

class GoalsState {
  const GoalsState({
    this.goals = const [],
    this.loaded = false,
    this.loadFailed = false,
  });

  /// Las más nuevas primero.
  final List<UserGoal> goals;
  final bool loaded;
  final bool loadFailed;

  List<UserGoal> get active =>
      goals.where((g) => g.status == GoalStatus.active).toList();

  UserGoal? byId(String id) => goals.where((g) => g.id == id).firstOrNull;

  /// La meta guardada con este `plan_id` del chat, si la hay.
  UserGoal? byPlanKey(String planKey) =>
      goals.where((g) => g.planKey == planKey).firstOrNull;

  /// La meta activa con este nombre (sin distinguir mayúsculas), si la hay.
  UserGoal? activeByLabel(String label) {
    final key = label.trim().toLowerCase();
    return active.where((g) => g.label.trim().toLowerCase() == key).firstOrNull;
  }
}

/// Único dueño de las metas: las leen la pestaña Metas y el chat (en cada
/// turno), las escriben la card del plan, las tools y la pantalla de la
/// meta. Después de escribir se vuelve a leer del servidor.
class GoalsNotifier extends StateNotifier<GoalsState> {
  GoalsNotifier(
    this._repo, {
    Set<String> Function()? heldTickers,
    Map<String, double> Function()? holdings,
    DateTime Function()? clock,
  }) : _holdings = holdings ?? (() => const {}),
       _heldTickers =
           heldTickers ??
           (holdings == null ? (() => const {}) : () => holdings().keys.toSet()),
       _clock = clock ?? DateTime.now,
       super(const GoalsState());

  final GoalsRepository _repo;
  final Set<String> Function() _heldTickers;

  /// Valor de mercado por ticker de la cartera (ver [goalHoldingsProvider]).
  final Map<String, double> Function() _holdings;
  final DateTime Function() _clock;

  Future<List<UserGoal>> load() async {
    try {
      final goals = await _repo.list();
      if (mounted) state = GoalsState(goals: goals, loaded: true);
      return goals;
    } catch (e) {
      debugPrint('[Goals] load: $e');
      if (mounted) {
        state = GoalsState(
          goals: state.goals,
          loaded: true,
          loadFailed: true,
        );
      }
      return state.goals;
    }
  }

  Future<List<UserGoal>> ensureLoaded() async =>
      state.loaded && !state.loadFailed ? state.goals : load();

  /// Tira [GoalsFailure]. Arranca contando lo que corresponde sin que el
  /// usuario haga nada: las inversiones de su compra mensual (las tenga ya
  /// o no: cuando las compre, se suman solas) o, para la jubilación (que
  /// parte del valor de la cartera), toda su cartera. Lo que ya cuenta para
  /// otra meta queda donde está.
  ///
  /// Si ya hay una meta activa con el mismo nombre (Porty rehízo el plan de
  /// "MacBook"), se actualiza esa en vez de duplicarla: plan nuevo, y suma
  /// los instrumentos nuevos a lo que ya contaba.
  Future<UserGoal> save(GoalDraft draft) async {
    final existing = state.activeByLabel(draft.label);
    final taken = {
      for (final g in state.active)
        if (g.id != existing?.id) ...g.linkedTickers,
    };
    final candidates =
        draft.snapshot.buyPlan.isNotEmpty
            ? {for (final e in draft.snapshot.buyPlan) e.ticker.toUpperCase()}
            : draft.type == GoalType.retirement
            ? _heldTickers()
            : const <String>{};
    if (existing != null) {
      await _repo.updatePlan(
        existing.id,
        draft,
        linkedTickers: {
          ...existing.linkedTickers,
          ...candidates.difference(taken),
        },
      );
      await load();
      return state.byId(existing.id) ?? existing;
    }
    final goal = await _repo.create(
      draft,
      linkedTickers: candidates.difference(taken),
    );
    await load();
    return state.byId(goal.id) ?? goal;
  }

  /// Qué inversiones cuentan para [goalId]. Cada ticker cuenta para una
  /// sola meta: si estaba en otra, se saca de ahí.
  Future<void> setLinkedTickers(String goalId, Set<String> tickers) async {
    final normalized = {for (final t in tickers) t.toUpperCase()};
    final moved = <String>{};
    for (final other in state.goals) {
      if (other.id == goalId) continue;
      final overlap = other.linkedTickers.intersection(normalized);
      if (overlap.isEmpty) continue;
      moved.add(other.id);
      await _repo.setLinkedTickers(
        other.id,
        other.linkedTickers.difference(overlap),
      );
    }
    await _repo.setLinkedTickers(goalId, normalized);
    await load();
    // Sumar una inversión que ya tiene (o sacarla) cambia lo que la meta
    // lleva juntado: el plan se rehace con eso, en esta meta y en la que la
    // perdió.
    await _rebase({goalId, ...moved});
  }

  /// Lo que tiene para la meta fuera de la app (reemplaza el monto
  /// anterior). El plan se recalcula partiendo de eso más sus inversiones
  /// asignadas. Tira [GoalsFailure].
  Future<void> setExternalSavings(String goalId, double amount) async {
    await _repo.setExternalSavings(goalId, amount < 0 ? 0 : amount);
    await load();
    await _rebase({goalId});
  }

  /// Rehace desde hoy el plan de cada meta de [ids] cuyo punto de partida
  /// ya no coincide con lo que tiene (ver [GoalReplan]).
  Future<void> _rebase(Set<String> ids) async {
    final holdings = _holdings();
    var changed = false;
    for (final id in ids) {
      final goal = state.byId(id);
      if (goal == null) continue;
      final draft = GoalReplan.rebase(
        goal,
        GoalReplan.capital(goal, holdings),
        _clock(),
      );
      if (draft == null) continue;
      await _repo.updatePlan(id, draft);
      changed = true;
    }
    if (changed) await load();
  }

  /// El usuario editó el plan de la meta [id] desde Metas. Lo que ya
  /// contaba sigue contando; se suman solo las inversiones nuevas del plan
  /// (las que el usuario sacó a mano no vuelven). [externalSavings]: lo que
  /// cargó en "Ahorros fuera de la app" desde el editor (el mismo dato).
  Future<void> updatePlan(
    String id,
    GoalDraft draft, {
    double? externalSavings,
  }) async {
    final goal = state.byId(id);
    if (goal == null) return;
    if (externalSavings != null && externalSavings != goal.externalSavings) {
      await _repo.setExternalSavings(
        id,
        externalSavings < 0 ? 0 : externalSavings,
      );
    }
    final before = {
      for (final e in goal.snapshot.buyPlan) e.ticker.toUpperCase(),
    };
    final taken = {
      for (final g in state.active)
        if (g.id != id) ...g.linkedTickers,
    };
    final added = {
      for (final e in draft.snapshot.buyPlan) e.ticker.toUpperCase(),
    }.difference(before).difference(taken);
    await _repo.updatePlan(
      id,
      draft,
      linkedTickers: {...goal.linkedTickers, ...added},
    );
    await load();
  }

  Future<void> setStatus(String id, GoalStatus status) async {
    await _repo.setStatus(id, status);
    await load();
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    if (mounted) {
      state = GoalsState(
        goals: state.goals.where((g) => g.id != id).toList(),
        loaded: true,
      );
    }
  }
}

final goalsProvider = StateNotifierProvider<GoalsNotifier, GoalsState>(
  (ref) => GoalsNotifier(
    ref.watch(goalsRepositoryProvider),
    holdings: () => ref.read(goalHoldingsProvider),
  ),
);

/// Valor de mercado por ticker (en mayúsculas) de la cartera: de acá sale
/// el progreso de cada meta.
final goalHoldingsProvider = Provider<Map<String, double>>((ref) {
  final valuations =
      ref.watch(homeProvider.select((s) => s.summary))?.valuations ?? const [];
  final map = <String, double>{};
  for (final v in valuations) {
    final t = v.position.ticker.toUpperCase();
    map[t] = (map[t] ?? 0) + v.marketValue;
  }
  return map;
});
