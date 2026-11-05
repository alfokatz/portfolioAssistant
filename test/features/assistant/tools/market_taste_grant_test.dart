// La consulta de mercado gratis del Free (spec 2026-11-03): cuándo se pide al
// servidor, qué abre y qué no. Correr:
// flutter test test/features/assistant/tools/market_taste_grant_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_toolset.dart';
import 'package:portfolio_assistant/features/assistant/tools/answer_guide.dart';
import 'package:portfolio_assistant/features/assistant/tools/market_taste_grant.dart';
import 'package:portfolio_assistant/features/assistant/tools/market_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/plan_tools.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/turn_activity.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';

import '../fakes/assistant_fakes.dart';

PendingToolCall _call(String name, List<String> tickers) =>
    PendingToolCall(name, {'tickers': tickers});

void main() {
  // heldSummary tiene AAPL y NVDA.
  AssistantToolContext ctx(SubscriptionTier tier) => AssistantToolContext(
    tier: tier,
    data: fakeDataSources(),
    summary: heldSummary,
  );

  MarketTasteGrant grant(
    AssistantToolContext c,
    FakeMarketTasteRepository repo, {
    bool available = true,
    String? turnId = 'turn-0001-abcd',
  }) => MarketTasteGrant(
    ctx: c,
    available: available,
    turnId: () => turnId,
    consume: repo.consume,
  );

  group('MarketTasteGrant', () {
    test('a round with a foreign ticker spends one lookup per turn and the '
        'market tools serve data', () async {
      final c = ctx(SubscriptionTier.free);
      final repo = FakeMarketTasteRepository();
      final g = grant(c, repo);

      await g.beforeRound([
        _call('get_quote', ['aapl', 'amzn']),
      ]);
      // Otra ronda del mismo turno: no vuelve a gastar.
      await g.beforeRound([
        _call('get_dividends', ['TSLA']),
      ]);

      expect(repo.consumed, hasLength(1));
      expect(repo.consumed.single.$1, 'turn-0001-abcd');
      expect(repo.consumed.single.$2, ['AMZN']);
      expect(c.marketTaste, isTrue);
      expect(c.marketTasteRemaining, 2);
      expect(c.marketDataServed, isTrue);
      expect(c.marketDataAllowed, isFalse);

      final quote = await GetQuoteTool(c).run({
        'tickers': ['AMZN'],
      });
      expect(quote['status'], 'ok');
      expect((quote['tickers'] as Map)['AMZN']['status'], isNot('locked'));
      expect(c.lockedReasons, isEmpty);
    });

    test('a round with only held tickers does not call the server', () async {
      final c = ctx(SubscriptionTier.free);
      final repo = FakeMarketTasteRepository();
      await grant(c, repo).beforeRound([
        _call('get_quote', ['AAPL', 'NVDA']),
        _call('get_news', ['AMZN']), // no es una tool de mercado
      ]);
      expect(repo.consumed, isEmpty);
      expect(c.marketTaste, isFalse);
    });

    test('premium, status off or no turn id: never calls the server', () async {
      final repo = FakeMarketTasteRepository();
      final round = [
        _call('get_quote', ['AMZN']),
      ];
      await grant(ctx(SubscriptionTier.premium), repo).beforeRound(round);
      await grant(ctx(SubscriptionTier.gold), repo).beforeRound(round);
      await grant(
        ctx(SubscriptionTier.free),
        repo,
        available: false,
      ).beforeRound(round);
      await grant(
        ctx(SubscriptionTier.free),
        repo,
        turnId: null,
      ).beforeRound(round);
      expect(repo.consumed, isEmpty);
    });

    test(
      'sends at most 6 foreign tickers, upper case, without repeats',
      () async {
        final c = ctx(SubscriptionTier.free);
        final repo = FakeMarketTasteRepository();
        await grant(c, repo).beforeRound([
          _call('get_dividends', ['a', 'b', 'c', 'd', 'e', 'f']),
          _call('get_quote', ['A', 'G', 'H']),
        ]);
        expect(repo.consumed.single.$2, ['A', 'B', 'C', 'D', 'E', 'F']);
      },
    );

    test(
      'the same turn id is idempotent (retry does not spend another)',
      () async {
        final repo = FakeMarketTasteRepository(used: 2);
        final round = [
          _call('get_quote', ['AMZN']),
        ];
        final first = ctx(SubscriptionTier.free);
        await grant(first, repo).beforeRound(round);
        final retry = ctx(SubscriptionTier.free);
        await grant(retry, repo).beforeRound(round);
        expect(first.marketTasteRemaining, 0);
        expect(retry.marketTaste, isTrue);
        expect(retry.marketTasteRemaining, 0);
      },
    );

    test('exhausted: the turn goes on with the flag set', () async {
      final c = ctx(SubscriptionTier.free);
      await grant(c, FakeMarketTasteRepository(used: 3)).beforeRound([
        _call('get_quote', ['AMZN']),
      ]);
      expect(c.marketTasteExhausted, isTrue);
      expect(c.marketTaste, isFalse);
      expect(c.marketDataServed, isFalse);
    });

    test(
      'server says disabled / not eligible / error: nothing changes',
      () async {
        final c = ctx(SubscriptionTier.free);
        await grant(c, FakeMarketTasteRepository(enabled: false)).beforeRound([
          _call('get_quote', ['AMZN']),
        ]);
        expect(c.marketTaste, isFalse);
        expect(c.marketTasteExhausted, isFalse);
      },
    );

    test('it does not open the Gold sources (the watchlist has its own '
        'limit, in every plan)', () async {
      final c = ctx(SubscriptionTier.free);
      await grant(c, FakeMarketTasteRepository()).beforeRound([
        _call('get_quote', ['AMZN']),
      ]);
      expect(c.marketTaste, isTrue);

      // La lista de seguimiento es de todos los planes: no la abre la
      // consulta gratis, tampoco la cierra.
      expect(c.watchlistAllowed, isTrue);
      final watch = await GetWatchlistTool(c).run({});
      expect(watch['status'], isNot('locked'));
      for (final tool in <DataTool>[
        GetFundamentalsTool(c),
        GetEarningsTool(c),
        GetNewsTool(c),
      ]) {
        final result = await tool.run({
          'tickers': ['AMZN'],
        });
        expect(result['status'], 'locked', reason: tool.name);
      }
    });
  });

  group('with no lookups left', () {
    AssistantToolContext exhausted() =>
        ctx(SubscriptionTier.free)..marketTasteExhausted = true;

    test(
      'locked results of the 3 market tools carry the answer guide',
      () async {
        final c = exhausted();
        final quote = await GetQuoteTool(c).run({
          'tickers': ['AMZN'],
        });
        final etf = await GetEtfHoldingsTool(c).run({
          'tickers': ['XLF'],
        });
        final dividends = await GetDividendsTool(c).run({
          'tickers': ['KO'],
        });
        for (final result in [quote, etf, dividends]) {
          expect(result['status'], 'locked');
          expect(
            result[AnswerGuide.key],
            AssistantToolContext.marketTasteExhaustedGuide,
          );
        }
        expect(
          AssistantToolContext.marketTasteExhaustedGuide,
          allOf(contains('Do not state any price'), contains('the app shows')),
        );
      },
    );

    test('a mixed result (one held, one foreign) keeps the guide', () async {
      final c = exhausted();
      final quote = await GetQuoteTool(c).run({
        'tickers': ['AAPL', 'AMZN'],
      });
      expect(quote['status'], 'ok');
      expect(quote[AnswerGuide.key], isNotNull);
    });

    test('without the exhausted flag there is no guide (as today)', () async {
      final c = ctx(SubscriptionTier.free);
      final quote = await GetQuoteTool(c).run({
        'tickers': ['AMZN'],
      });
      expect(quote.containsKey(AnswerGuide.key), isFalse);
    });

    test('the paywall does not cut the turn for market data, but other '
        'reasons still do', () async {
      final c = exhausted();
      final locked = await GetQuoteTool(c).run({
        'tickers': ['AMZN'],
      });
      final round = [
        ToolCallRecord(name: 'get_quote', args: const {}, result: locked),
      ];
      expect(c.lockedReasons, {PaywallReason.marketDataLocked});
      expect(AssistantTurnPolicy.paywallFor(round, c), isNull);

      c.lockedReasons.add(PaywallReason.simulations);
      expect(
        AssistantTurnPolicy.paywallFor([
          ...round,
          ToolCallRecord(
            name: 'get_invest_candidates',
            args: const {},
            result: const {'status': 'locked'},
          ),
        ], c)?.reason,
        PaywallReason.simulations,
      );
    });

    test(
      'disabled / error (flag not set): the turn is cut as before',
      () async {
        final c = ctx(SubscriptionTier.free);
        final locked = await GetQuoteTool(c).run({
          'tickers': ['AMZN'],
        });
        expect(
          AssistantTurnPolicy.paywallFor([
            ToolCallRecord(name: 'get_quote', args: const {}, result: locked),
          ], c),
          const ChatPaywall(
            PaywallReason.marketDataLocked,
            'chat_turn_locked_market_data',
            PlanFeature.marketData,
          ),
        );
      },
    );
  });
}
