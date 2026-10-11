import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/goals/data/goals_repository.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';

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
}

/// Único dueño de las metas: las leen la pestaña Metas y el chat (en cada
/// turno), las escriben la card del plan, las tools y la pantalla de la
/// meta. Después de escribir se vuelve a leer: los aportes y el estado
/// salen siempre del servidor.
class GoalsNotifier extends StateNotifier<GoalsState> {
  GoalsNotifier(this._repo) : super(const GoalsState());

  final GoalsRepository _repo;

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

  /// Tira [GoalsFailure].
  Future<UserGoal> save(GoalDraft draft) async {
    final goal = await _repo.create(draft);
    await load();
    return state.byId(goal.id) ?? goal;
  }

  /// Tira [GoalsFailure].
  Future<void> addContribution(
    String goalId, {
    required double amount,
    DateTime? date,
    String? note,
    String source = 'app',
  }) async {
    await _repo.addContribution(
      goalId,
      amount: amount,
      date: date ?? DateTime.now(),
      note: note,
      source: source,
    );
    await load();
  }

  Future<void> removeContribution(String id) async {
    await _repo.deleteContribution(id);
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
  (ref) => GoalsNotifier(ref.watch(goalsRepositoryProvider)),
);
