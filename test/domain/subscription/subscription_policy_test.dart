import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_limits.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';

void main() {
  group('SubscriptionTier', () {
    test('fromStorageString parses known tiers', () {
      expect(
        SubscriptionTier.fromStorageString('premium'),
        SubscriptionTier.premium,
      );
      expect(
        SubscriptionTier.fromStorageString('gold'),
        SubscriptionTier.gold,
      );
    });

    test('fromStorageString defaults to free for unknown values', () {
      expect(SubscriptionTier.fromStorageString(null), SubscriptionTier.free);
      expect(SubscriptionTier.fromStorageString(''), SubscriptionTier.free);
      expect(
        SubscriptionTier.fromStorageString('unknown'),
        SubscriptionTier.free,
      );
    });

    test('toStorageString round-trips with fromStorageString', () {
      for (final tier in SubscriptionTier.values) {
        expect(
          SubscriptionTier.fromStorageString(tier.toStorageString()),
          tier,
        );
      }
    });

    test('monthlyQuota returns tier-specific limits', () {
      expect(SubscriptionTier.free.monthlyQuota, 20);
      expect(SubscriptionTier.premium.monthlyQuota, 500);
      expect(SubscriptionTier.gold.monthlyQuota, 1000);
    });
  });

  group('AiUsageLimits', () {
    test('monthlyQuota returns tier-specific limits', () {
      expect(
        AiUsageLimits.monthlyQuota(SubscriptionTier.free),
        AiUsageLimits.freeMonthly,
      );
      expect(
        AiUsageLimits.monthlyQuota(SubscriptionTier.premium),
        AiUsageLimits.premiumMonthly,
      );
      expect(
        AiUsageLimits.monthlyQuota(SubscriptionTier.gold),
        AiUsageLimits.goldMonthly,
      );
    });
  });

  group('SubscriptionPolicy.isModeAllowed', () {
    test('free allows portfolio and learn only', () {
      expect(
        SubscriptionPolicy.isModeAllowed(
          SubscriptionTier.free,
          AssistantMode.portfolio,
        ),
        isTrue,
      );
      expect(
        SubscriptionPolicy.isModeAllowed(
          SubscriptionTier.free,
          AssistantMode.learn,
        ),
        isTrue,
      );
      expect(
        SubscriptionPolicy.isModeAllowed(
          SubscriptionTier.free,
          AssistantMode.explore,
        ),
        isFalse,
      );
      expect(
        SubscriptionPolicy.isModeAllowed(
          SubscriptionTier.free,
          AssistantMode.invest,
        ),
        isFalse,
      );
      expect(
        SubscriptionPolicy.isModeAllowed(
          SubscriptionTier.free,
          AssistantMode.plan,
        ),
        isFalse,
      );
    });

    test('premium adds explore to free modes', () {
      expect(
        SubscriptionPolicy.isModeAllowed(
          SubscriptionTier.premium,
          AssistantMode.portfolio,
        ),
        isTrue,
      );
      expect(
        SubscriptionPolicy.isModeAllowed(
          SubscriptionTier.premium,
          AssistantMode.learn,
        ),
        isTrue,
      );
      expect(
        SubscriptionPolicy.isModeAllowed(
          SubscriptionTier.premium,
          AssistantMode.explore,
        ),
        isTrue,
      );
      expect(
        SubscriptionPolicy.isModeAllowed(
          SubscriptionTier.premium,
          AssistantMode.invest,
        ),
        isFalse,
      );
      expect(
        SubscriptionPolicy.isModeAllowed(
          SubscriptionTier.premium,
          AssistantMode.plan,
        ),
        isFalse,
      );
    });

    test('gold allows all modes', () {
      for (final mode in AssistantMode.values) {
        expect(
          SubscriptionPolicy.isModeAllowed(SubscriptionTier.gold, mode),
          isTrue,
        );
      }
    });
  });

  group('SubscriptionPolicy.positionLimit', () {
    test('free tier is capped at 10 positions', () {
      expect(
        SubscriptionPolicy.positionLimit(SubscriptionTier.free),
        AiUsageLimits.freePositionLimit,
      );
    });

    test('premium and gold have unlimited positions', () {
      expect(SubscriptionPolicy.positionLimit(SubscriptionTier.premium), isNull);
      expect(SubscriptionPolicy.positionLimit(SubscriptionTier.gold), isNull);
    });
  });

  group('SubscriptionPolicy.isBenchmarkAllowed', () {
    test('free tier cannot access benchmark', () {
      expect(
        SubscriptionPolicy.isBenchmarkAllowed(SubscriptionTier.free),
        isFalse,
      );
    });

    test('premium and gold can access benchmark', () {
      expect(
        SubscriptionPolicy.isBenchmarkAllowed(SubscriptionTier.premium),
        isTrue,
      );
      expect(
        SubscriptionPolicy.isBenchmarkAllowed(SubscriptionTier.gold),
        isTrue,
      );
    });
  });

  group('SubscriptionPolicy.isNewsAllowed', () {
    test('only gold tier can use news queries', () {
      expect(
        SubscriptionPolicy.isNewsAllowed(SubscriptionTier.free),
        isFalse,
      );
      expect(
        SubscriptionPolicy.isNewsAllowed(SubscriptionTier.premium),
        isFalse,
      );
      expect(
        SubscriptionPolicy.isNewsAllowed(SubscriptionTier.gold),
        isTrue,
      );
    });
  });

  group('SubscriptionPolicy.queryWeight', () {
    test('news queries consume 3 units', () {
      expect(
        SubscriptionPolicy.queryWeight(isNewsQuery: true),
        AiUsageLimits.newsQueryWeight,
      );
    });

    test('standard queries consume 1 unit', () {
      expect(
        SubscriptionPolicy.queryWeight(isNewsQuery: false),
        AiUsageLimits.standardQueryWeight,
      );
    });
  });
}
