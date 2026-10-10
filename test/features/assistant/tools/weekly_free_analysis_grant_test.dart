import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/market_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/weekly_free_analysis_grant.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/turn_activity.dart';

import '../fakes/assistant_fakes.dart';

List<PendingToolCall> _analysisRound(String ticker) => [
  for (final name in const [
    'get_quote',
    'get_fundamentals',
    'get_earnings',
    'get_news',
  ])
    PendingToolCall(name, {
      'tickers': [ticker],
    }),
];

void main() {
  AssistantToolContext ctx(SubscriptionTier tier) => AssistantToolContext(
    tier: tier,
    data: fakeDataSources(),
    summary: heldSummary, // AAPL, NVDA
  );

  test('only the 3 Gold sources for ONE ticker count as an analysis', () {
    expect(WeeklyFreeAnalysisGrant.analysisTicker(_analysisRound('bac')), 'BAC');
    expect(
      WeeklyFreeAnalysisGrant.analysisTicker([
        const PendingToolCall('get_news', {
          'tickers': ['BAC'],
        }),
      ]),
      isNull,
    );
    expect(
      WeeklyFreeAnalysisGrant.analysisTicker([
        ..._analysisRound('BAC'),
        const PendingToolCall('get_news', {
          'tickers': ['JPM'],
        }),
      ]),
      isNull,
    );
  });

  test('premium: an analysis round spends it once and serves Gold data, '
      'tagged as courtesy', () async {
    final c = ctx(SubscriptionTier.premium);
    var consumed = 0;
    final grant = WeeklyFreeAnalysisGrant(
      ctx: c,
      available: true,
      consume: (_) async {
        consumed++;
        return true;
      },
    );
    await grant.beforeRound(_analysisRound('BAC'));
    await grant.beforeRound(_analysisRound('BAC'));
    expect(consumed, 1);
    expect(grant.used, isTrue);
    final result = await GetFundamentalsTool(c).run({
      'tickers': ['BAC'],
    });
    expect(result['status'], isNot('locked'));
    expect(result['courtesy'], 'weekly_free_analysis');
    // Otro ticker en el mismo turno sigue bloqueado.
    final other = await GetNewsTool(c).run({
      'tickers': ['JPM'],
    });
    expect(other['status'], 'locked');
  });

  test('a lone news question never spends it', () async {
    final c = ctx(SubscriptionTier.premium);
    var consumed = 0;
    final grant = WeeklyFreeAnalysisGrant(
      ctx: c,
      available: true,
      consume: (_) async {
        consumed++;
        return true;
      },
    );
    await grant.beforeRound([
      const PendingToolCall('get_news', {
        'tickers': ['BAC'],
      }),
    ]);
    expect(consumed, 0);
    expect(
      (await GetNewsTool(c).run({
        'tickers': ['BAC'],
      }))['status'],
      'locked',
    );
  });

  test('free: own tickers only (it opens Gold, not Premium market data)',
      () async {
    final c = ctx(SubscriptionTier.free);
    var consumed = 0;
    Future<bool> consume(String _) async {
      consumed++;
      return true;
    }

    await WeeklyFreeAnalysisGrant(
      ctx: c,
      available: true,
      consume: consume,
    ).beforeRound(_analysisRound('BAC'));
    expect(consumed, 0);
    await WeeklyFreeAnalysisGrant(
      ctx: c,
      available: true,
      consume: consume,
    ).beforeRound(_analysisRound('AAPL'));
    expect(consumed, 1);
    expect(c.courtesyTicker, 'AAPL');
  });

  test('already used (server says no) → stays locked', () async {
    final c = ctx(SubscriptionTier.premium);
    await WeeklyFreeAnalysisGrant(
      ctx: c,
      available: true,
      consume: (_) async => false,
    ).beforeRound(_analysisRound('BAC'));
    expect(c.courtesyTicker, isNull);
    expect(
      (await GetEarningsTool(c).run({
        'tickers': ['BAC'],
      }))['status'],
      'locked',
    );
  });

  test('gold never touches it', () async {
    var consumed = 0;
    await WeeklyFreeAnalysisGrant(
      ctx: ctx(SubscriptionTier.gold),
      available: true,
      consume: (_) async {
        consumed++;
        return true;
      },
    ).beforeRound(_analysisRound('BAC'));
    expect(consumed, 0);
  });
}
