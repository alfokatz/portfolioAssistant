import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/domain/entities/subscription_status.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SubscriptionSupabaseDataSource {
  SubscriptionSupabaseDataSource({
    required SupabaseClient client,
    required SupabaseAuthService authService,
  })  : _client = client,
        _authService = authService;

  final SupabaseClient _client;
  final SupabaseAuthService _authService;

  Future<SubscriptionStatus> fetchStatus() async {
    _authService.requireUserId();
    final response = await _client.rpc('get_subscription_status');
    final map = Map<String, dynamic>.from(response as Map);
    return _parseStatus(map);
  }

  Future<bool> consumeQuota(int weight) async {
    _authService.requireUserId();
    final response = await _client.rpc(
      'consume_ai_quota',
      params: {'p_weight': weight},
    );
    final map = Map<String, dynamic>.from(response as Map);
    return map['ok'] == true;
  }

  SubscriptionStatus _parseStatus(Map<String, dynamic> map) {
    return SubscriptionStatus(
      tier: SubscriptionTier.fromStorageString(map['tier'] as String?),
      queriesUsed: (map['queries_used'] as num?)?.toInt() ?? 0,
      queriesLimit: (map['queries_limit'] as num?)?.toInt() ?? 0,
      month: map['month'] as String? ?? '',
    );
  }
}

final subscriptionSupabaseDataSourceProvider =
    Provider<SubscriptionSupabaseDataSource>(
  (ref) => SubscriptionSupabaseDataSource(
    client: ref.watch(supabaseClientProvider),
    authService: ref.watch(supabaseAuthServiceProvider),
  ),
);
