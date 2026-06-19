import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_limits.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/news_query_detector.dart';

void main() {
  group('Assistant subscription gating via SubscriptionPolicy', () {
    group('mode access per tier', () {
      test('free tier can only access portfolio and learn', () {
        const allowed = [AssistantMode.portfolio, AssistantMode.learn];
        const locked = [
          AssistantMode.explore,
          AssistantMode.invest,
          AssistantMode.plan,
        ];

        for (final mode in allowed) {
          expect(
            SubscriptionPolicy.isModeAllowed(SubscriptionTier.free, mode),
            isTrue,
            reason: 'free should allow $mode',
          );
        }
        for (final mode in locked) {
          expect(
            SubscriptionPolicy.isModeAllowed(SubscriptionTier.free, mode),
            isFalse,
            reason: 'free should block $mode',
          );
        }
      });

      test('premium tier adds explore to free modes', () {
        const allowed = [
          AssistantMode.portfolio,
          AssistantMode.learn,
          AssistantMode.explore,
        ];
        const locked = [AssistantMode.invest, AssistantMode.plan];

        for (final mode in allowed) {
          expect(
            SubscriptionPolicy.isModeAllowed(SubscriptionTier.premium, mode),
            isTrue,
          );
        }
        for (final mode in locked) {
          expect(
            SubscriptionPolicy.isModeAllowed(SubscriptionTier.premium, mode),
            isFalse,
          );
        }
      });

      test('gold tier unlocks all assistant modes', () {
        for (final mode in AssistantMode.values) {
          expect(
            SubscriptionPolicy.isModeAllowed(SubscriptionTier.gold, mode),
            isTrue,
          );
        }
      });
    });

    group('news query gating', () {
      test('only gold tier allows news enrichment', () {
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

      test('news detector identifies news-related queries', () {
        expect(isNewsQuery('¿Qué noticias hay de NVDA?'), isTrue);
        expect(isNewsQuery('What happened to Tesla this week?'), isTrue);
        expect(isNewsQuery('Compare NVDA vs AMD'), isFalse);
      });

      test('news queries consume higher quota weight', () {
        expect(
          SubscriptionPolicy.queryWeight(isNewsQuery: true),
          AiUsageLimits.newsQueryWeight,
        );
        expect(
          SubscriptionPolicy.queryWeight(isNewsQuery: false),
          AiUsageLimits.standardQueryWeight,
        );
        expect(
          SubscriptionPolicy.queryWeight(isNewsQuery: true),
          greaterThan(
            SubscriptionPolicy.queryWeight(isNewsQuery: false),
          ),
        );
      });
    });
  });
}
