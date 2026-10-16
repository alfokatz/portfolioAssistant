import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/features/allocation/domain/allocation_plan.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

sealed class AllocationFailure implements Exception {
  const AllocationFailure();
}

/// El plan de cartera es de Premium (la base cortó con
/// `allocation_plan_requires_premium`).
class AllocationLocked extends AllocationFailure {
  const AllocationLocked();
}

class AllocationUnavailable extends AllocationFailure {
  const AllocationUnavailable();
}

/// `allocation_plans` en Supabase (RLS: cada usuario el suyo).
class AllocationRepository {
  AllocationRepository({required SupabaseClient? Function() client})
    : _client = client;

  final SupabaseClient? Function() _client;

  static const _table = 'allocation_plans';

  SupabaseClient? get _signedIn {
    final client = _client();
    if (client == null || client.auth.currentUser == null) return null;
    return client;
  }

  /// El plan guardado, o `null` si nunca armó uno.
  Future<AllocationPlan?> load() async {
    final client = _signedIn;
    if (client == null) return null;
    try {
      final row =
          await client
              .from(_table)
              .select('targets, drift_threshold, notify')
              .maybeSingle();
      return row == null ? null : AllocationPlan.fromRow(row);
    } on PostgrestException {
      throw const AllocationUnavailable();
    }
  }

  Future<void> save(AllocationPlan plan) async {
    final client = _signedIn;
    if (client == null) throw const AllocationUnavailable();
    try {
      await client.from(_table).upsert({
        'user_id': client.auth.currentUser!.id,
        ...plan.toRow(),
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('allocation_plan_requires_premium')) {
        throw const AllocationLocked();
      }
      throw const AllocationUnavailable();
    }
  }
}

final allocationRepositoryProvider = Provider<AllocationRepository>(
  (ref) => AllocationRepository(
    client: () {
      try {
        return ref.read(supabaseClientProvider);
      } catch (_) {
        return null;
      }
    },
  ),
);
