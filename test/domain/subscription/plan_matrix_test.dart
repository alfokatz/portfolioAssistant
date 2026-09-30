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

/// La tabla acordada (2026-09-30): feature → planes que la incluyen.
const _expected = <PlanFeature, Set<SubscriptionTier>>{
  PlanFeature.ownPortfolio: {_free, _premium, _gold},
  PlanFeature.marketData: {_premium, _gold},
  PlanFeature.benchmark: {_premium, _gold},
  PlanFeature.unlimitedPositions: {_premium, _gold},
  PlanFeature.investSimulation: {_premium, _gold},
  PlanFeature.goals: {_premium, _gold},
  PlanFeature.companyAnalysis: {_gold},
  PlanFeature.news: {_gold},
  PlanFeature.earnings: {_gold},
  PlanFeature.fundamentals: {_gold},
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
        PlanMatrix.of(_premium).features.containsAll(PlanMatrix.of(_free).features),
        isTrue,
      );
      expect(
        PlanMatrix.of(_gold).features.containsAll(PlanMatrix.of(_premium).features),
        isTrue,
      );
    });

    test('query limits unchanged: 20 / 500 / 1000', () {
      expect(_free.monthlyQuota, 20);
      expect(_premium.monthlyQuota, 500);
      expect(_gold.monthlyQuota, 1000);
      expect(AiUsageLimits.goldMonthly, 1000);
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
