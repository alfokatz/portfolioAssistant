import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/assistant/tools/action_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/answer_guide.dart';
import 'package:portfolio_assistant/features/assistant/tools/share_classes.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/portfolio_tools.dart';

import '../fakes/assistant_fakes.dart';

/// Precio fijo por día: el cierre de cada fecha es conocido.
class _Quotes implements QuoteRepository {
  _Quotes({this.fail = false});

  final bool fail;
  final dailyCalls = <String>[];

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String t) async =>
      const Right(999);

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String t,
  ) async {
    dailyCalls.add(t);
    if (fail) return Left(HttpError(code: 'x'));
    return Right([
      PriceCandle(date: DateTime(2025, 1, 2), close: 100),
      PriceCandle(date: DateTime(2026, 9, 25), close: 200), // viernes
      PriceCandle(date: DateTime(2026, 9, 28), close: 210),
    ]);
  }

  @override
  Future<List<PriceCandle>> getIntradayCandles(String t) async => const [];
}

PositionValuation _lot(String id, String ticker, double qty, DateTime date) =>
    PositionValuation(
      position: Position(
        id: id,
        ticker: ticker,
        quantity: qty,
        purchasePrice: 150,
        purchaseDate: date,
      ),
      currentPrice: 200,
      marketValue: qty * 200,
      pnlAbsolute: qty * 50,
      pnlPercent: 33,
    );

/// TSLA en dos compras (10 + 5), AAPL en una.
final _summary = PortfolioSummary(
  totalValue: 4000,
  totalCostBasis: 3000,
  totalPnlAbsolute: 1000,
  totalPnlPercent: 33,
  valuations: [
    valuation('TSLA', qty: 15),
    valuation('AAPL', qty: 5),
  ],
  lots: [
    _lot('tsla-new', 'TSLA', 5, DateTime(2026, 3, 1)),
    _lot('tsla-old', 'TSLA', 10, DateTime(2025, 6, 1)),
    _lot('aapl-1', 'AAPL', 5, DateTime(2025, 2, 1)),
  ],
);

AssistantToolContext _ctx({
  SubscriptionTier tier = SubscriptionTier.premium,
  _Quotes? quotes,
}) => AssistantToolContext(
  tier: tier,
  data: fakeDataSources(quotes: quotes ?? _Quotes()),
  summary: _summary,
  now: DateTime(2026, 9, 29),
);

ActionProposal _proposal(Map<String, Object?> result) {
  expect(result['status'], 'ok', reason: '$result');
  return ActionProposal.fromToolResult(result)!;
}

/// El resultado sin su `answer_guide` (lo cubre el grupo de guías).
Map<String, Object?> _data(Map<String, Object?> result) =>
    {...result}..remove(AnswerGuide.key);

void main() {
  group('plan', () {
    test('portfolio actions are in every plan: no tool is locked', () async {
      for (final tier in SubscriptionTier.values) {
        final ctx = _ctx(tier: tier);
        for (final tool in ActionTools.build(ctx)) {
          final result = await tool.run({
            'ticker': 'TSLA',
            'shares': 1,
            'date': '2026-09-25',
          });
          expect(
            result['status'],
            isNot('locked'),
            reason: '${tool.name} × ${tier.name}',
          );
          expect(ctx.lockedReasons, isEmpty);
          expect(ctx.lockedFeatures, isEmpty);
        }
      }
    });

    test('tool names match ActionTools.names', () {
      expect(
        ActionTools.build(_ctx()).map((t) => t.name).toSet(),
        ActionTools.names,
      );
    });
  });

  // eval action-ambiguous-company: "Compré 5 acciones de Alphabet" y el
  // modelo proponía GOOGL sin preguntar (se salteaba search_symbol).
  group('share classes: never guess GOOGL vs GOOG', () {
    AssistantToolContext ctxSaying(String question, {List<String> held = const []}) =>
        AssistantToolContext(
          tier: SubscriptionTier.premium,
          data: fakeDataSources(quotes: _Quotes()),
          summary: PortfolioSummary(
            totalValue: 1000,
            totalCostBasis: 1000,
            totalPnlAbsolute: 0,
            totalPnlPercent: 0,
            valuations: [for (final t in held) valuation(t, qty: 1)],
          ),
          now: DateTime(2026, 9, 29),
          userQuestion: question,
        );

    const buy = {'ticker': 'GOOGL', 'shares': 5, 'date': '2026-09-25'};

    test('the company name only → ambiguous with both classes, no proposal',
        () async {
      final result = await ProposeBuyTool(
        ctxSaying('Compré 5 acciones de Alphabet el 25 de septiembre'),
      ).run(buy);
      expect(result['status'], 'ambiguous');
      expect(result['reason'], 'share_class');
      expect(
        (result['matches'] as List).map((m) => (m as Map)['symbol']),
        ['GOOGL', 'GOOG'],
      );
      expect(result[AnswerGuide.key], ShareClasses.guide);
      expect(result.containsKey('proposal_id'), isFalse);
    });

    test('the user wrote the ticker → proposes as always', () async {
      final result = await ProposeBuyTool(
        ctxSaying('Compré 5 GOOGL el 25 de septiembre'),
      ).run(buy);
      expect(result['status'], isNot('ambiguous'));
      // "GOOG" escrito no es "GOOGL": sigue siendo la clase C.
      final c = await ProposeBuyTool(
        ctxSaying('Compré 5 GOOG el 25 de septiembre'),
      ).run({...buy, 'ticker': 'GOOG'});
      expect(c['status'], isNot('ambiguous'));
    });

    test('holding exactly that class is not ambiguous; the other one is',
        () async {
      final same = await ProposeBuyTool(
        ctxSaying('Compré 5 de Alphabet', held: ['GOOGL']),
      ).run(buy);
      expect(same['status'], isNot('ambiguous'));
      final other = await ProposeBuyTool(
        ctxSaying('Compré 5 de Alphabet', held: ['GOOG']),
      ).run(buy);
      expect(other['status'], 'ambiguous');
    });

    test('sells too; other tickers and unknown user text are untouched',
        () async {
      final sell = await ProposeSellTool(
        ctxSaying('Vendí 2 de Berkshire', held: ['BRK-A', 'BRK-B']),
      ).run({'ticker': 'BRK.B', 'shares': 2, 'date': '2026-09-25'});
      expect(sell['status'], 'ambiguous');
      final aapl = await ProposeBuyTool(
        ctxSaying('Compré 5 de Apple'),
      ).run({...buy, 'ticker': 'AAPL'});
      expect(aapl['status'], isNot('ambiguous'));
      final unknown = await ProposeBuyTool(_ctx()).run(buy);
      expect(unknown['status'], isNot('ambiguous'));
    });
  });

  group('propose_buy position limit', () {
    PortfolioSummary summaryOf(int n) => PortfolioSummary(
      totalValue: 1000,
      totalCostBasis: 1000,
      totalPnlAbsolute: 0,
      totalPnlPercent: 0,
      valuations: [for (var i = 0; i < n; i++) valuation('T$i', qty: 1)],
    );

    AssistantToolContext ctxWith(SubscriptionTier tier, int n) =>
        AssistantToolContext(
          tier: tier,
          data: fakeDataSources(quotes: _Quotes()),
          summary: summaryOf(n),
          now: DateTime(2026, 9, 29),
        );

    const buy = {'ticker': 'NEWCO', 'shares': 1, 'date': '2026-09-28'};

    test('Free with 10 holdings: a new ticker is limit_reached', () async {
      final result = await ProposeBuyTool(
        ctxWith(SubscriptionTier.free, 10),
      ).run(buy);
      expect(result['status'], 'limit_reached');
      expect(result['limit'], 10);
      expect(result[AnswerGuide.key], ActionGuides.positionLimit);
      expect(result.containsKey('proposal_id'), isFalse);
    });

    test('the 11th ticker is refused before asking for date or quantity', () async {
      final result = await ProposeBuyTool(
        ctxWith(SubscriptionTier.free, 10),
      ).run({'ticker': 'NEWCO'});
      expect(result['status'], 'limit_reached');
    });

    test('Free with 9 holdings can still add the 10th ticker', () async {
      final result = await ProposeBuyTool(
        ctxWith(SubscriptionTier.free, 9),
      ).run(buy);
      expect(result['status'], 'ok');
    });

    test('Free at the limit can still buy more of a ticker it holds', () async {
      final result = await ProposeBuyTool(
        ctxWith(SubscriptionTier.free, 10),
      ).run({...buy, 'ticker': 't3'});
      expect(result['status'], 'ok');
    });

    test('Premium has no limit', () async {
      final result = await ProposeBuyTool(
        ctxWith(SubscriptionTier.premium, 40),
      ).run(buy);
      expect(result['status'], 'ok');
    });

    test('a limit_reached never opens a turn paywall', () async {
      final ctx = ctxWith(SubscriptionTier.free, 10);
      await ProposeBuyTool(ctx).run(buy);
      expect(ctx.lockedReasons, isEmpty);
    });
  });

  group('propose_buy', () {
    test('complete data → proposal with that day\'s close', () async {
      final quotes = _Quotes();
      final result = await ProposeBuyTool(
        _ctx(quotes: quotes),
      ).run({'ticker': 'aapl', 'shares': 10, 'date': '2026-09-28'});
      final p = _proposal(result);
      expect(p.kind, ActionKind.buy);
      expect(p.ticker, 'AAPL');
      expect(p.shares, 10);
      expect(p.unit, AmountUnit.shares);
      expect(p.price, 210);
      expect(p.priceSource, PriceSource.closeOnDate);
      expect(p.date, DateTime(2026, 9, 28));
      expect(p.id, isNotEmpty);
      expect(quotes.dailyCalls, ['AAPL']);
    });

    test('a ticker imported from eToro can still get a manual buy '
        '(only selling or deleting imported shares is read-only)', () async {
      final imported = PositionValuation(
        position: Position(
          id: 'ewz-etoro',
          ticker: 'EWZ',
          quantity: 20,
          purchasePrice: 28,
          purchaseDate: DateTime(2025, 3, 1),
          source: PositionSource.etoro,
        ),
        currentPrice: 30,
        marketValue: 600,
        pnlAbsolute: 40,
        pnlPercent: 7,
      );
      final ctx = AssistantToolContext(
        tier: SubscriptionTier.premium,
        data: fakeDataSources(quotes: _Quotes()),
        summary: PortfolioSummary(
          totalValue: 600,
          totalCostBasis: 560,
          totalPnlAbsolute: 40,
          totalPnlPercent: 7,
          valuations: [imported],
          lots: [imported],
        ),
        now: DateTime(2026, 9, 29),
      );
      final p = _proposal(
        await ProposeBuyTool(
          ctx,
        ).run({'ticker': 'EWZ', 'shares': 5, 'date': '2026-09-28'}),
      );
      expect(p.kind, ActionKind.buy);
      expect(p.ticker, 'EWZ');
      // Vender lo importado sí sigue siendo de eToro.
      final sell = await ProposeSellTool(
        ctx,
      ).run({'ticker': 'EWZ', 'shares': 5, 'date': '2026-09-28'});
      expect(sell['reason'], 'managed_by_broker');
    });

    test('each call gets a new proposal id', () async {
      final tool = ProposeBuyTool(_ctx());
      final args = {'ticker': 'AAPL', 'shares': 1, 'date': '2026-09-28'};
      final a = _proposal(await tool.run(args));
      final b = _proposal(await tool.run(args));
      expect(a.id, isNot(b.id));
    });

    test('a weekend date uses the last close before it', () async {
      final p = _proposal(
        await ProposeBuyTool(
          _ctx(),
        ).run({'ticker': 'AAPL', 'shares': 1, 'date': '2026-09-27'}),
      );
      expect(p.price, 200);
    });

    test('USD amount → shares at that price', () async {
      final p = _proposal(
        await ProposeBuyTool(
          _ctx(),
        ).run({'ticker': 'NVDA', 'amount_usd': 500, 'date': '2026-09-25'}),
      );
      expect(p.unit, AmountUnit.usd);
      expect(p.amountUsd, 500);
      expect(p.shares, 2.5);
    });

    test('the price the user said wins over the close', () async {
      final p = _proposal(
        await ProposeBuyTool(_ctx()).run({
          'ticker': 'AAPL',
          'shares': 2,
          'date': '2026-09-25',
          'price_usd': 180,
        }),
      );
      expect(p.price, 180);
      expect(p.priceSource, PriceSource.user);
    });

    test('missing data → needs_input listing all of it', () async {
      final tool = ProposeBuyTool(_ctx());
      expect(_data(await tool.run({'ticker': 'AAPL'})), {
        'status': 'needs_input',
        'missing': ['quantity', 'date'],
      });
      expect((await tool.run({'shares': 3, 'date': '2026-09-25'}))['missing'], [
        'ticker',
      ]);
      expect(
        (await tool.run({'ticker': 'AAPL', 'amount_usd': 100}))['missing'],
        ['date'],
      );
    });

    test('a month alone is not a date', () async {
      final result = await ProposeBuyTool(
        _ctx(),
      ).run({'ticker': 'AAPL', 'shares': 1, 'date': '2026-03'});
      expect(result['missing'], ['date']);
    });

    test('future date → invalid', () async {
      final result = await ProposeBuyTool(
        _ctx(),
      ).run({'ticker': 'AAPL', 'shares': 1, 'date': '2026-09-30'});
      expect(_data(result), {'status': 'invalid', 'reason': 'future_date'});
    });

    test('zero or negative quantity → invalid', () async {
      for (final args in [
        {'ticker': 'AAPL', 'shares': 0, 'date': '2026-09-25'},
        {'ticker': 'AAPL', 'amount_usd': -5, 'date': '2026-09-25'},
      ]) {
        expect(
          (await ProposeBuyTool(_ctx()).run(args))['reason'],
          'invalid_quantity',
        );
      }
    });

    test('without history and without a price from the user → failed', () async {
      final result = await ProposeBuyTool(
        _ctx(quotes: _Quotes(fail: true)),
      ).run({'ticker': 'ZZZZ', 'shares': 1, 'date': '2026-09-25'});
      expect(result, {'status': 'failed', 'reason': 'price_unavailable'});
    });

    test('without history but with the user\'s price → proposal', () async {
      final p = _proposal(
        await ProposeBuyTool(_ctx(quotes: _Quotes(fail: true))).run({
          'ticker': 'AAPL',
          'shares': 1,
          'date': '2026-09-25',
          'price_usd': 190,
        }),
      );
      expect(p.price, 190);
    });

    test('a date before all history → proposal without price', () async {
      final p = _proposal(
        await ProposeBuyTool(
          _ctx(),
        ).run({'ticker': 'AAPL', 'amount_usd': 300, 'date': '2020-05-04'}),
      );
      expect(p.price, isNull);
      expect(p.priceSource, PriceSource.missing);
      expect(p.shares, isNull, reason: 'USD without price: the card asks');
      expect(p.amountUsd, 300);
    });
  });

  group('propose_sell', () {
    test('partial sale with its lots, oldest first', () async {
      final p = _proposal(
        await ProposeSellTool(
          _ctx(),
        ).run({'ticker': 'TSLA', 'shares': 12, 'date': '2026-09-28'}),
      );
      expect(p.kind, ActionKind.sell);
      expect(p.shares, 12);
      expect(p.heldShares, 15);
      expect(p.price, 210);
      expect(p.lots.map((l) => l.id), ['tsla-old', 'tsla-new']);
    });

    test('all=true sells everything held', () async {
      final p = _proposal(
        await ProposeSellTool(
          _ctx(),
        ).run({'ticker': 'TSLA', 'all': true, 'date': '2026-09-28'}),
      );
      expect(p.shares, 15);
      expect(p.unit, AmountUnit.shares);
    });

    test('USD amount → shares at that day\'s price', () async {
      final p = _proposal(
        await ProposeSellTool(
          _ctx(),
        ).run({'ticker': 'TSLA', 'amount_usd': 1000, 'date': '2026-09-25'}),
      );
      expect(p.shares, 5);
      expect(p.unit, AmountUnit.usd);
    });

    test('something not held → invalid not_held', () async {
      final result = await ProposeSellTool(
        _ctx(),
      ).run({'ticker': 'MSFT', 'all': true, 'date': '2026-09-25'});
      expect(_data(result), {'status': 'invalid', 'reason': 'not_held'});
    });

    test('more than held → invalid with held_shares', () async {
      final result = await ProposeSellTool(
        _ctx(),
      ).run({'ticker': 'TSLA', 'shares': 20, 'date': '2026-09-25'});
      expect(_data(result), {
        'status': 'invalid',
        'reason': 'exceeds_holdings',
        'held_shares': 15.0,
      });
    });

    test('before the first purchase → invalid', () async {
      final result = await ProposeSellTool(
        _ctx(),
      ).run({'ticker': 'TSLA', 'all': true, 'date': '2025-05-01'});
      expect(result['reason'], 'sale_before_purchase');
      expect(result['first_purchase_date'], '2025-06-01');
    });

    test('missing quantity and date → needs_input', () async {
      expect(_data(await ProposeSellTool(_ctx()).run({'ticker': 'TSLA'})), {
        'status': 'needs_input',
        'missing': ['quantity', 'date'],
      });
    });

    test('future date → invalid', () async {
      final result = await ProposeSellTool(
        _ctx(),
      ).run({'ticker': 'TSLA', 'all': true, 'date': '2027-01-01'});
      expect(result['reason'], 'future_date');
    });
  });

  group('PORTFOLIO_BRIEF', () {
    test('lists the operations of the conversation, when there are', () {
      final actions = [
        {'proposal_id': 'p1', 'status': 'confirmed', 'ticker': 'AAPL'},
      ];
      final ctx = AssistantToolContext(
        tier: SubscriptionTier.premium,
        data: fakeDataSources(),
        summary: _summary,
        actionsThisConversation: actions,
        now: DateTime(2026, 9, 29),
      );
      expect(PortfolioBrief.build(ctx)[PortfolioBrief.actionsKey], actions);
      expect(
        PortfolioBrief.build(_ctx()).containsKey(PortfolioBrief.actionsKey),
        isFalse,
      );
    });
  });

  group('propose_delete_position', () {
    test('lists the lots of a held ticker, without date or price', () async {
      final quotes = _Quotes();
      final p = _proposal(
        await ProposeDeletePositionTool(
          _ctx(quotes: quotes),
        ).run({'ticker': 'TSLA'}),
      );
      expect(p.kind, ActionKind.delete);
      expect(p.heldShares, 15);
      expect(p.lots.map((l) => l.id), ['tsla-old', 'tsla-new']);
      expect(p.date, isNull);
      expect(p.price, isNull);
      expect(quotes.dailyCalls, isEmpty);
    });

    test('not held → invalid', () async {
      expect(
        (await ProposeDeletePositionTool(_ctx()).run({'ticker': 'MSFT'}))['reason'],
        'not_held',
      );
    });

    test('without ticker → needs_input', () async {
      expect(_data(await ProposeDeletePositionTool(_ctx()).run({})), {
        'status': 'needs_input',
        'missing': ['ticker'],
      });
    });
  });

  group('answer_guide', () {
    String? guideOf(Map<String, Object?> r) => r[AnswerGuide.key] as String?;

    test('ok, needs_input, invalid y limit_reached traen su guía', () async {
      expect(
        guideOf(
          await ProposeBuyTool(
            _ctx(quotes: _Quotes()),
          ).run({'ticker': 'AAPL', 'shares': 10, 'date': '2026-09-28'}),
        ),
        ActionGuides.ok,
      );
      expect(
        guideOf(await ProposeSellTool(_ctx()).run({'ticker': 'TSLA'})),
        ActionGuides.needsInput,
      );
      expect(
        guideOf(
          await ProposeSellTool(
            _ctx(),
          ).run({'ticker': 'MSFT', 'all': true, 'date': '2026-09-25'}),
        ),
        ActionGuides.invalid,
      );
      // La card lee el mismo resultado: la guía no la rompe.
      expect(
        _proposal(
          await ProposeBuyTool(
            _ctx(quotes: _Quotes()),
          ).run({'ticker': 'AAPL', 'shares': 10, 'date': '2026-09-28'}),
        ).ticker,
        'AAPL',
      );
      // Free con la cartera en el tope y un ticker nuevo.
      expect(
        guideOf(
          await ProposeBuyTool(
            AssistantToolContext(
              tier: SubscriptionTier.free,
              data: fakeDataSources(quotes: _Quotes()),
              summary: PortfolioSummary(
                totalValue: 1000,
                totalCostBasis: 1000,
                totalPnlAbsolute: 0,
                totalPnlPercent: 0,
                valuations: [
                  for (var i = 0; i < 10; i++) valuation('T$i', qty: 1),
                ],
              ),
              now: DateTime(2026, 9, 29),
            ),
          ).run({'ticker': 'NEWCO', 'shares': 1, 'date': '2026-09-28'}),
        ),
        ActionGuides.positionLimit,
      );
    });
  });
}
