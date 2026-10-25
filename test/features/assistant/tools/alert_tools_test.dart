import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/assistant/tools/action_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/alert_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';

import '../fakes/assistant_fakes.dart';

class _Quotes implements QuoteRepository {
  _Quotes(this.price);

  final double? price;

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String t) async =>
      price == null ? Left(HttpError(code: 'x')) : Right(price!);

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String t,
  ) async => const Right([]);

  @override
  Future<List<PriceCandle>> getIntradayCandles(String t) async => const [];
}

AssistantToolContext _ctx({
  double? price = 720,
  SubscriptionTier tier = SubscriptionTier.free,
  Future<List<Map<String, Object?>>> Function()? alerts,
}) => AssistantToolContext(
  tier: tier,
  data: fakeDataSources(quotes: _Quotes(price)),
  loadPriceAlerts: alerts,
  now: DateTime(2026, 10, 13),
);

void main() {
  group('propose_price_alert', () {
    test('prepares the card (Free too: the limit is checked on confirm)', () async {
      final result = await ProposePriceAlertTool(_ctx()).run({
        'ticker': 'voo',
        'condition': 'above',
        'target': 750,
        'repeat': true,
      });
      expect(result['status'], 'ok');
      final proposal = ActionProposal.fromToolResult(result)!;
      expect(proposal.kind, ActionKind.alert);
      expect(proposal.ticker, 'VOO');
      expect(proposal.price, 720);
      expect(proposal.alertCondition, 'above');
      expect(proposal.alertTarget, 750);
      expect(proposal.alertRepeatDaily, isTrue);
    });

    test('missing target or direction → needs_input', () async {
      final result = await ProposePriceAlertTool(_ctx()).run({'ticker': 'AAPL'});
      expect(result, {
        'status': 'needs_input',
        'missing': ['target'],
      });
      final noTicker = await ProposePriceAlertTool(_ctx()).run({
        'condition': 'below',
        'target': 100,
      });
      expect(noTicker['missing'], ['ticker']);
    });

    test('a price already there → invalid already_met, with the price', () async {
      final result = await ProposePriceAlertTool(_ctx()).run({
        'ticker': 'VOO',
        'condition': 'below',
        'target': 800,
      });
      expect(result['status'], 'invalid');
      expect(result['reason'], 'already_met');
      expect(result['current_price'], 720);
    });

    test('percent out of range, unknown ticker', () async {
      expect(
        (await ProposePriceAlertTool(_ctx()).run({
          'ticker': 'NVDA',
          'condition': 'pct_down',
          'target': 95,
        }))['reason'],
        'percent_range',
      );
      expect(
        (await ProposePriceAlertTool(_ctx(price: null)).run({
          'ticker': 'ZZZZ',
          'condition': 'above',
          'target': 10,
        }))['reason'],
        'price_unavailable',
      );
    });

    test('its card is a QaActionProposal like the portfolio actions', () {
      expect(ActionTools.proposalTools, contains(AlertTools.proposePriceAlert));
      expect(ActionTools.names, isNot(contains(AlertTools.proposePriceAlert)));
    });
  });

  group('list_price_alerts', () {
    test('returns the alerts, or empty', () async {
      final ok = await ListPriceAlertsTool(
        _ctx(
          alerts:
              () async => [
                {'symbol': 'VOO', 'condition': 'above', 'target': 750},
              ],
        ),
      ).run(const {});
      expect(ok['status'], 'ok');
      expect((ok['alerts'] as List).single, containsPair('symbol', 'VOO'));

      final empty = await ListPriceAlertsTool(
        _ctx(alerts: () async => const []),
      ).run(const {});
      expect(empty['status'], 'empty');

      final none = await ListPriceAlertsTool(_ctx()).run(const {});
      expect(none['status'], 'failed');
    });
  });
}
