import 'package:portfolio_assistant/domain/entities/subscription_status.dart';

abstract class SubscriptionRepository {
  Future<SubscriptionStatus> fetchStatus();

  /// Returns `true` when quota was consumed; `false` when exceeded.
  Future<bool> consumeQuota(int weight);
}
