import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/features/goals/domain/goal_progress.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

sealed class GoalsFailure implements Exception {
  const GoalsFailure();
}

class GoalLimitReached extends GoalsFailure {
  const GoalLimitReached();
}

class GoalsUnavailable extends GoalsFailure {
  const GoalsUnavailable();
}

/// `user_goals` en Supabase (RLS: cada usuario las suyas).
class GoalsRepository {
  GoalsRepository({required SupabaseClient? Function() client})
    : _client = client;

  final SupabaseClient? Function() _client;

  static const _goals = 'user_goals';
  static const _select =
      'id, label, goal_type, target_amount, target_date, plan, status, '
      'created_at, plan_key, linked_tickers, external_savings';

  SupabaseClient? get _signedIn {
    final client = _client();
    if (client == null || client.auth.currentUser == null) return null;
    return client;
  }

  Future<List<UserGoal>> list() async {
    final client = _signedIn;
    if (client == null) return const [];
    final rows = await client
        .from(_goals)
        .select(_select)
        .order('created_at', ascending: false);
    return [
      for (final r in rows) UserGoal.fromRow(Map<String, dynamic>.from(r)),
    ].whereType<UserGoal>().toList();
  }

  /// Guarda la meta. Si ya había una con el mismo plan, devuelve esa.
  Future<UserGoal> create(
    GoalDraft draft, {
    Set<String> linkedTickers = const {},
  }) async {
    final client = _signedIn;
    if (client == null) throw const GoalsUnavailable();
    try {
      final row =
          await client
              .from(_goals)
              .insert({
                'user_id': client.auth.currentUser!.id,
                'label': draft.label,
                'goal_type': draft.type.storageValue,
                'target_amount': draft.targetAmount,
                'target_date': GoalProgress.formatDate(draft.targetDate),
                'plan': draft.snapshot.toJson(),
                'plan_key': draft.planKey,
                'linked_tickers': linkedTickers.toList(),
              })
              .select(_select)
              .single();
      return UserGoal.fromRow(row) ?? (throw const GoalsUnavailable());
    } on PostgrestException catch (e) {
      if (e.code == '23505' && draft.planKey != null) {
        final row =
            await client
                .from(_goals)
                .select(_select)
                .eq('plan_key', draft.planKey!)
                .single();
        return UserGoal.fromRow(row) ?? (throw const GoalsUnavailable());
      }
      if (e.message.contains('user_goal_limit_reached')) {
        throw const GoalLimitReached();
      }
      throw const GoalsUnavailable();
    }
  }

  Future<void> setStatus(String id, GoalStatus status) async {
    final client = _signedIn;
    if (client == null) throw const GoalsUnavailable();
    await client
        .from(_goals)
        .update({'status': status.storageValue})
        .eq('id', id);
  }

  Future<void> delete(String id) async {
    final client = _signedIn;
    if (client == null) throw const GoalsUnavailable();
    await client.from(_goals).delete().eq('id', id);
  }

  Future<void> setLinkedTickers(String id, Set<String> tickers) async {
    final client = _signedIn;
    if (client == null) throw const GoalsUnavailable();
    await client
        .from(_goals)
        .update({'linked_tickers': tickers.toList()})
        .eq('id', id);
  }

  Future<void> setExternalSavings(String id, double amount) async {
    final client = _signedIn;
    if (client == null) throw const GoalsUnavailable();
    try {
      await client
          .from(_goals)
          .update({'external_savings': amount})
          .eq('id', id);
    } on PostgrestException {
      throw const GoalsUnavailable();
    }
  }
}

final goalsRepositoryProvider = Provider<GoalsRepository>(
  (ref) => GoalsRepository(
    client: () {
      try {
        return ref.read(supabaseClientProvider);
      } catch (_) {
        return null;
      }
    },
  ),
);
