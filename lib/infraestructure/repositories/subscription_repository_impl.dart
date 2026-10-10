import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/subscription_status.dart';
import 'package:portfolio_assistant/domain/repositories/subscription_repository.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/supabase/subscription_supabase_data_source.dart';

class SubscriptionRepositoryImpl implements SubscriptionRepository {
  SubscriptionRepositoryImpl({required SubscriptionSupabaseDataSource dataSource})
      : _dataSource = dataSource;

  final SubscriptionSupabaseDataSource _dataSource;

  @override
  Future<SubscriptionStatus> fetchStatus() => _dataSource.fetchStatus();

  @override
  Future<bool> consumeQuota(int weight) => _dataSource.consumeQuota(weight);
}

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>(
  (ref) => SubscriptionRepositoryImpl(
    dataSource: ref.watch(subscriptionSupabaseDataSourceProvider),
  ),
);
