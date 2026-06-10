import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/invest_context_builder.dart';

class _FakeQuoteRepository implements QuoteRepository {
  static const nvdaPrice = 120.0;
  static const xomPrice = 110.0;

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async {
    switch (ticker) {
      case 'NVDA':
        return const Right(nvdaPrice);
      case 'XOM':
        return const Right(xomPrice);
      case 'BAD':
        return Left(HttpError(code: 'not_found'));
      default:
        return Left(HttpError(code: 'unknown'));
    }
  }

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) async {
    if (ticker == 'NVDA' || ticker == 'XOM') {
      final end = DateTime(2026, 6, 10);
      return Right(
        List<PriceCandle>.generate(
          10,
          (i) => PriceCandle(
            date: end.subtract(Duration(days: 9 - i)),
            close: 100.0 + i * 2,
          ),
        ),
      );
    }
    return Left(HttpError(code: 'not_found'));
  }
}

void main() {
  group('InvestContextBuilder', () {
    final fixedAsOf = DateTime.utc(2026, 6, 10, 12, 0);
    final quoteRepository = _FakeQuoteRepository();

    test('builds snapshot with budget and ticker from message', () async {
      final snapshot = await InvestContextBuilder.build(
        userMessage: 'Quiero invertir \$500 en NVDA',
        quoteRepository: quoteRepository,
        riskProfile: 0.6,
        asOf: fixedAsOf,
      );

      expect(snapshot['mode'], 'invest');
      expect(snapshot['data_source'], 'yahoo_finance');
      expect(snapshot['as_of'], fixedAsOf.toIso8601String());
      expect(snapshot['has_budget'], isTrue);
      expect(snapshot['budget_usd'], 500.0);
      expect(snapshot['risk_profile'], 0.6);

      final candidates = snapshot['candidates'] as List<dynamic>;
      expect(candidates.length, 1);

      final nvda = candidates.first as Map<String, dynamic>;
      expect(nvda['ticker'], 'NVDA');
      expect(nvda['fetch_ok'], isTrue);
      expect(nvda['current_price'], _FakeQuoteRepository.nvdaPrice);
      expect(nvda['sector'], 'Technology');
      expect(nvda.containsKey('week_change_pct'), isTrue);
      expect(nvda['fit_score'], 100);
    });

    test('uses keyword defaults when no tickers in message', () async {
      final snapshot = await InvestContextBuilder.build(
        userMessage: 'Quiero invertir en energía con \$200',
        quoteRepository: quoteRepository,
        asOf: fixedAsOf,
      );

      final candidates = snapshot['candidates'] as List<dynamic>;
      final tickers =
          candidates.map((c) => (c as Map)['ticker'] as String).toList();
      expect(tickers, contains('XOM'));
      expect(snapshot['has_budget'], isTrue);
      expect(snapshot['budget_usd'], 200.0);
    });

    test('includes sector concentration and warning from portfolio', () async {
      final summary = PortfolioSummary(
        totalValue: 1000,
        totalCostBasis: 900,
        totalPnlAbsolute: 100,
        totalPnlPercent: 11.11,
        valuations: [
          PositionValuation(
            position: Position(
              id: '1',
              ticker: 'AAPL',
              quantity: 2,
              purchasePrice: 100,
              purchaseDate: DateTime(2024, 1, 1),
            ),
            currentPrice: 150,
            marketValue: 450,
            pnlAbsolute: 100,
            pnlPercent: 50,
          ),
          PositionValuation(
            position: Position(
              id: '2',
              ticker: 'MSFT',
              quantity: 1,
              purchasePrice: 200,
              purchaseDate: DateTime(2024, 1, 1),
            ),
            currentPrice: 550,
            marketValue: 550,
            pnlAbsolute: 100,
            pnlPercent: 14.29,
          ),
        ],
      );

      final snapshot = await InvestContextBuilder.build(
        userMessage: 'Invertir en NVDA',
        quoteRepository: quoteRepository,
        summary: summary,
        asOf: fixedAsOf,
      );

      final concentration =
          snapshot['sector_concentration'] as Map<String, dynamic>;
      expect(concentration['Technology'], 100.0);
      expect(snapshot['concentration_warning'], isTrue);
      expect(snapshot['overweight_sector'], 'Technology');

      final candidates = snapshot['candidates'] as List<dynamic>;
      final nvda = candidates.first as Map<String, dynamic>;
      expect(nvda['fit_score'], lessThan(100));
    });

    test('marks fetch_ok false and lowers fit_score on quote failure', () async {
      final snapshot = await InvestContextBuilder.build(
        userMessage: 'Invertir BAD',
        quoteRepository: quoteRepository,
        asOf: fixedAsOf,
      );

      final candidates = snapshot['candidates'] as List<dynamic>;
      final bad = candidates.first as Map<String, dynamic>;
      expect(bad['fetch_ok'], isFalse);
      expect(bad.containsKey('current_price'), isFalse);
      expect(bad['fit_score'], lessThan(70));
    });

    test('diversifying candidate scores higher than overweight sector match', () async {
      final summary = PortfolioSummary(
        totalValue: 1000,
        totalCostBasis: 900,
        totalPnlAbsolute: 100,
        totalPnlPercent: 11.11,
        valuations: [
          PositionValuation(
            position: Position(
              id: '1',
              ticker: 'AAPL',
              quantity: 5,
              purchasePrice: 100,
              purchaseDate: DateTime(2024, 1, 1),
            ),
            currentPrice: 100,
            marketValue: 500,
            pnlAbsolute: 0,
            pnlPercent: 0,
          ),
          PositionValuation(
            position: Position(
              id: '2',
              ticker: 'MSFT',
              quantity: 5,
              purchasePrice: 100,
              purchaseDate: DateTime(2024, 1, 1),
            ),
            currentPrice: 100,
            marketValue: 500,
            pnlAbsolute: 0,
            pnlPercent: 0,
          ),
        ],
      );

      final techSnapshot = await InvestContextBuilder.build(
        userMessage: 'Invertir \$100 en NVDA',
        quoteRepository: quoteRepository,
        summary: summary,
        asOf: fixedAsOf,
      );
      final energySnapshot = await InvestContextBuilder.build(
        userMessage: 'Invertir \$100 en XOM',
        quoteRepository: quoteRepository,
        summary: summary,
        asOf: fixedAsOf,
      );

      final techFit =
          ((techSnapshot['candidates'] as List).first
                  as Map<String, dynamic>)['fit_score']
              as int;
      final energyFit =
          ((energySnapshot['candidates'] as List).first
                  as Map<String, dynamic>)['fit_score']
              as int;

      expect(energyFit, greaterThan(techFit));
    });
  });
}
