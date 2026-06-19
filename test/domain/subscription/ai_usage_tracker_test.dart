import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_status.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/subscription_repository.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_limits.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_tracker.dart';

class _FakeSubscriptionRepository implements SubscriptionRepository {
  SubscriptionStatus status = const SubscriptionStatus(
    tier: SubscriptionTier.free,
    queriesUsed: 0,
    queriesLimit: AiUsageLimits.freeMonthly,
    month: '2026-06',
  );

  int consumeCalls = 0;

  @override
  Future<SubscriptionStatus> fetchStatus() async => status;

  @override
  Future<bool> consumeQuota(int weight) async {
    consumeCalls++;
    if (status.queriesUsed + weight > status.queriesLimit) {
      return false;
    }
    status = SubscriptionStatus(
      tier: status.tier,
      queriesUsed: status.queriesUsed + weight,
      queriesLimit: status.queriesLimit,
      month: status.month,
    );
    return true;
  }
}

void main() {
  group('AiUsageTracker', () {
    late _FakeSubscriptionRepository repository;
    late AiUsageTracker tracker;

    setUp(() {
      repository = _FakeSubscriptionRepository();
      tracker = AiUsageTracker(repository: repository);
    });

    test('getStatus returns server status', () async {
      repository.status = const SubscriptionStatus(
        tier: SubscriptionTier.premium,
        queriesUsed: 42,
        queriesLimit: AiUsageLimits.premiumMonthly,
        month: '2026-06',
      );

      final status = await tracker.getStatus();

      expect(status.tier, SubscriptionTier.premium);
      expect(status.queriesUsed, 42);
      expect(status.queriesLimit, AiUsageLimits.premiumMonthly);
    });

    test('canConsume respects server quota', () async {
      repository.status = SubscriptionStatus(
        tier: SubscriptionTier.free,
        queriesUsed: AiUsageLimits.freeMonthly,
        queriesLimit: AiUsageLimits.freeMonthly,
        month: '2026-06',
      );

      expect(
        await tracker.canConsume(AiUsageLimits.standardQueryWeight),
        isFalse,
      );
    });

    test('recordUsage delegates to consumeQuota RPC', () async {
      final ok = await tracker.recordUsage(AiUsageLimits.newsQueryWeight);

      expect(ok, isTrue);
      expect(repository.consumeCalls, 1);
      expect(repository.status.queriesUsed, 3);
    });

    test('recordUsage returns false when quota exceeded', () async {
      repository.status = SubscriptionStatus(
        tier: SubscriptionTier.free,
        queriesUsed: 19,
        queriesLimit: AiUsageLimits.freeMonthly,
        month: '2026-06',
      );

      final ok = await tracker.recordUsage(AiUsageLimits.newsQueryWeight);

      expect(ok, isFalse);
      expect(repository.status.queriesUsed, 19);
    });
  });
}
