import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/goals/data/goals_repository.dart';
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
  GoalsNotifier(this._repo, {Set<String> Function()? heldTickers})
    : _heldTickers = heldTickers ?? (() => const {}),
      super(const GoalsState());

  final GoalsRepository _repo;
  final Set<String> Function() _heldTickers;

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
    for (final other in state.goals) {
      if (other.id == goalId) continue;
      final overlap = other.linkedTickers.intersection(normalized);
      if (overlap.isEmpty) continue;
      await _repo.setLinkedTickers(
        other.id,
        other.linkedTickers.difference(overlap),
      );
    }
    await _repo.setLinkedTickers(goalId, normalized);
    await load();
  }

  /// Lo que tiene para la meta fuera de la app (reemplaza el monto
  /// anterior). Tira [GoalsFailure].
  Future<void> setExternalSavings(String goalId, double amount) async {
    await _repo.setExternalSavings(goalId, amount < 0 ? 0 : amount);
    await load();
  }

  /// El usuario editó el plan de la meta [id] desde Metas. Lo que ya
  /// contaba sigue contando; se suman solo las inversiones nuevas del plan
  /// (las que el usuario sacó a mano no vuelven).
  Future<void> updatePlan(String id, GoalDraft draft) async {
    final goal = state.byId(id);
    if (goal == null) return;
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
    heldTickers: () => ref.read(goalHoldingsProvider).keys.toSet(),
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
