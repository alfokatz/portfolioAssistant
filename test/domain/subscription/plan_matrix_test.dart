import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_limits.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/assistant/tools/advice_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/market_tools.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';

import '../../features/assistant/fakes/assistant_fakes.dart';

const _free = SubscriptionTier.free;
const _premium = SubscriptionTier.premium;
const _gold = SubscriptionTier.gold;

/// La tabla acordada (2026-09-30; 2026-11-05: operaciones por chat en Free y
/// noticias de lo que tenés en Premium): feature → planes que la incluyen.
const _expected = <PlanFeature, Set<SubscriptionTier>>{
  PlanFeature.ownPortfolio: {_free, _premium, _gold},
  PlanFeature.marketData: {_premium, _gold},
  PlanFeature.benchmark: {_premium, _gold},
  PlanFeature.unlimitedPositions: {_premium, _gold},
  PlanFeature.investSimulation: {_premium, _gold},
  PlanFeature.goals: {_premium, _gold},
  PlanFeature.portfolioActions: {_free, _premium, _gold},
  PlanFeature.companyAnalysis: {_gold},
  PlanFeature.news: {_gold},
  PlanFeature.heldNews: {_premium, _gold},
  PlanFeature.earnings: {_gold},
  PlanFeature.fundamentals: {_gold},
  PlanFeature.brokerSync: {_premium, _gold},
  PlanFeature.multiBrokerSync: {_gold},
  PlanFeature.brokerManualRefresh: {_gold},
  PlanFeature.allocationPlan: {_premium, _gold},
};

void main() {
  group('matrix: every feature × plan', () {
    for (final feature in PlanFeature.values) {
      for (final tier in SubscriptionTier.values) {
        test('${feature.name} × ${tier.name}', () {
          expect(
            PlanMatrix.allows(tier, feature),
            _expected[feature]!.contains(tier),
          );
        });
      }
    }

    test('each plan includes everything of the plan below', () {
      expect(
        PlanMatrix.of(
          _premium,
        ).features.containsAll(PlanMatrix.of(_free).features),
        isTrue,
      );
      expect(
        PlanMatrix.of(
          _gold,
        ).features.containsAll(PlanMatrix.of(_premium).features),
        isTrue,
      );
    });

    test('query limits unchanged: 20 / 500 / 1000', () {
      expect(_free.monthlyQuota, 20);
      expect(_premium.monthlyQuota, 500);
      expect(_gold.monthlyQuota, 1000);
      expect(AiUsageLimits.goldMonthly, 1000);
    });

    test('quota nudge: only Free warns, at 5 left', () {
      expect(PlanMatrix.of(_free).quotaNudgeAtRemaining, 5);
      expect(PlanMatrix.of(_premium).quotaNudgeAtRemaining, isNull);
      expect(PlanMatrix.of(_gold).quotaNudgeAtRemaining, isNull);
    });

    test('market data tastes: Free 3, Premium and Gold 0', () {
      expect(PlanMatrix.of(_free).marketDataTastesPerMonth, 3);
      expect(PlanMatrix.of(_premium).marketDataTastesPerMonth, 0);
      expect(PlanMatrix.of(_gold).marketDataTastesPerMonth, 0);
    });

    test('watchlist limits: Free 3, Premium 30, Gold 100', () {
      expect(PlanMatrix.of(_free).watchlistLimit, 3);
      expect(PlanMatrix.of(_premium).watchlistLimit, 30);
      expect(PlanMatrix.of(_gold).watchlistLimit, 100);
    });

    test('allowsNewsFor: Gold all, Premium only held, Free none', () {
      for (final held in [true, false]) {
        expect(PlanMatrix.allowsNewsFor(_gold, held: held), isTrue);
        expect(PlanMatrix.allowsNewsFor(_free, held: held), isFalse);
      }
      expect(PlanMatrix.allowsNewsFor(_premium, held: true), isTrue);
      expect(PlanMatrix.allowsNewsFor(_premium, held: false), isFalse);
      expect(SubscriptionPolicy.isNewsAllowedFor(_premium, held: true), isTrue);
      expect(
        SubscriptionPolicy.isNewsAllowedFor(_premium, held: false),
        isFalse,
      );
    });

    test('nextTier: free -> premium -> gold -> null', () {
      expect(PlanMatrix.nextTier(_free), _premium);
      expect(PlanMatrix.nextTier(_premium), _gold);
      expect(PlanMatrix.nextTier(_gold), isNull);
    });

    test('weekly free analysis: Free and Premium, never Gold', () {
      expect(PlanMatrix.hasWeeklyFreeAnalysis(_free), isTrue);
      expect(PlanMatrix.hasWeeklyFreeAnalysis(_premium), isTrue);
      expect(PlanMatrix.hasWeeklyFreeAnalysis(_gold), isFalse);
    });
  });

  group('gating, paywall and subscription screen read the same matrix', () {
    test('SubscriptionPolicy is the matrix', () {
      for (final tier in SubscriptionTier.values) {
        expect(
          SubscriptionPolicy.isMarketDataAllowed(tier),
          PlanMatrix.allows(tier, PlanFeature.marketData),
        );
        expect(
          SubscriptionPolicy.isNewsAllowed(tier),
          PlanMatrix.allows(tier, PlanFeature.news),
        );
        expect(
          SubscriptionPolicy.positionLimit(tier),
          PlanMatrix.of(tier).positionLimit,
        );
      }
    });

    test('each data tool is locked exactly when the matrix says so', () async {
      final args = {
        'tickers': ['BAC'],
      };
      for (final tier in SubscriptionTier.values) {
        final ctx = AssistantToolContext(tier: tier, data: fakeDataSources());
        final cases = {
          PlanFeature.fundamentals: GetFundamentalsTool(ctx),
          PlanFeature.earnings: GetEarningsTool(ctx),
          PlanFeature.news: GetNewsTool(ctx),
          PlanFeature.investSimulation: GetInvestCandidatesTool(ctx),
        };
        for (final entry in cases.entries) {
          final result = await entry.value.run(args);
          expect(
            result['status'] == 'locked',
            !PlanMatrix.allows(tier, entry.key),
            reason: '${entry.value.name} × ${tier.name}',
          );
          if (result['status'] == 'locked') {
            expect(
              result['required_plan'],
              PlanMatrix.minimumTier(entry.key).name,
            );
          }
        }
      }
    });

    test('the paywall lists the matrix highlights of each plan', () {
      for (final tier in [_premium, _gold]) {
        expect(
          SubscriptionPaywallSheet.featureKeysFor(tier),
          containsAll(PlanMatrix.marketingKeys(tier)),
        );
      }
    });

    test('highlights are features the plan includes', () {
      for (final tier in SubscriptionTier.values) {
        final spec = PlanMatrix.of(tier);
        expect(spec.features.containsAll(spec.highlights), isTrue);
      }
    });

    test('Premium marketing: held news in, simulations and benchmark out', () {
      expect(PlanMatrix.marketingKeys(_premium), [
        'plan_feature_broker_sync',
        'plan_feature_unlimited_positions',
        'plan_feature_held_news',
        'plan_feature_allocation_plan',
        'plan_feature_goals',
        'plan_feature_market_data',
      ]);
    });

    test('Gold marketing leads with the weekly report', () {
      expect(PlanMatrix.marketingKeys(_gold), [
        'plan_feature_weekly_report',
        'plan_feature_multi_broker_sync',
        'plan_feature_company_analysis',
        'plan_feature_news',
        'plan_feature_earnings',
      ]);
    });

    test('Gold paywall closes with "everything in Premium"', () {
      final keys = SubscriptionPaywallSheet.featureKeysFor(_gold);
      expect(keys.last, 'plan_feature_everything_premium');
      expect(keys.first, 'plan_feature_weekly_report');
      expect(
        SubscriptionPaywallSheet.featureKeysFor(_premium),
        isNot(contains('plan_feature_everything_premium')),
      );
    });

    test('every PlanFeature has a label key in both translations', () {
      for (final path in [
        'assets/translations/es-ES.json',
        'assets/translations/en-US.json',
      ]) {
        final keys =
            (jsonDecode(File(path).readAsStringSync()) as Map).keys.toSet();
        for (final f in PlanFeature.values) {
          expect(keys, contains(PlanMatrix.labelKey(f)), reason: path);
        }
      }
    });

    test('every marketing key exists in both translations', () {
      for (final path in [
        'assets/translations/es-ES.json',
        'assets/translations/en-US.json',
      ]) {
        final keys =
            (jsonDecode(File(path).readAsStringSync()) as Map).keys.toSet();
        for (final tier in SubscriptionTier.values) {
          for (final key in [
            ...PlanMatrix.marketingKeys(tier),
            ...SubscriptionPaywallSheet.featureKeysFor(tier),
          ]) {
            expect(keys, contains(key), reason: '$key en $path');
          }
        }
      }
    });
  });
}
