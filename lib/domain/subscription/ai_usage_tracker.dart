import 'package:portfolio_assistant/domain/entities/subscription_status.dart';
import 'package:portfolio_assistant/domain/repositories/subscription_repository.dart';

class AiUsageTracker {
  AiUsageTracker({required SubscriptionRepository repository})
      : _repository = repository;

  final SubscriptionRepository _repository;

  Future<SubscriptionStatus> getStatus() => _repository.fetchStatus();

  Future<bool> canConsume(int weight) async {
    final status = await _repository.fetchStatus();
    return status.queriesUsed + weight <= status.queriesLimit;
  }

  Future<bool> recordUsage(int weight) => _repository.consumeQuota(weight);
}
