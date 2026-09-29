import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_limits.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';

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

  group('SubscriptionPolicy per-data access', () {
    test('market data for non-held tickers: premium and gold', () {
      expect(
        SubscriptionPolicy.isMarketDataAllowed(SubscriptionTier.free),
        isFalse,
      );
      expect(
        SubscriptionPolicy.isMarketDataAllowed(SubscriptionTier.premium),
        isTrue,
      );
      expect(
        SubscriptionPolicy.isMarketDataAllowed(SubscriptionTier.gold),
        isTrue,
      );
    });

    test('investment simulation and goal planning: gold only', () {
      expect(SubscriptionPolicy.isAdviceAllowed(SubscriptionTier.free), isFalse);
      expect(
        SubscriptionPolicy.isAdviceAllowed(SubscriptionTier.premium),
        isFalse,
      );
      expect(SubscriptionPolicy.isAdviceAllowed(SubscriptionTier.gold), isTrue);
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
    test('news queries consume the news weight (1 since Google News RSS)', () {
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
