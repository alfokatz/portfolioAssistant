import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_fundamentals.dart';
import 'package:portfolio_assistant/domain/repositories/company_fundamentals_repository.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_fundamentals_enricher.dart';

class _FakeCompanyFundamentalsRepository
    implements CompanyFundamentalsRepository {
  _FakeCompanyFundamentalsRepository({this.onGetFundamentals});

  final Future<Either<HttpError, CompanyFundamentals?>> Function(String)?
  onGetFundamentals;

  @override
  Future<Either<HttpError, CompanyFundamentals?>> getFundamentals(
    String ticker,
  ) {
    return onGetFundamentals?.call(ticker) ?? Future.value(const Right(null));
  }
}

void main() {
  group('ExploreFundamentalsEnricher', () {
    const baseSnapshot = <String, Object?>{
      'mode': 'explore',
      'explore_tickers': {
        'AAPL': {'fetch_ok': true},
      },
    };

    test('marks status empty when there are no tickers in the snapshot', () async {
      final enricher = ExploreFundamentalsEnricher(
        fundamentalsRepository: _FakeCompanyFundamentalsRepository(),
      );

      final result = await enricher.enrich(
        snapshot: const {
          'mode': 'explore',
          'explore_tickers': <String, Object?>{},
        },
      );

      expect(result['fundamentals_status'], 'empty');
      expect(result['fundamentals'], isEmpty);
    });

    test('marks status empty when the repository has no data', () async {
      final enricher = ExploreFundamentalsEnricher(
        fundamentalsRepository: _FakeCompanyFundamentalsRepository(),
      );

      final result = await enricher.enrich(
        snapshot: Map<String, Object?>.from(baseSnapshot),
      );

      expect(result['fundamentals_status'], 'empty');
      expect(result['fundamentals'], isEmpty);
    });

    test(
      'maps the curated fields into snake_case keys under the ticker',
      () async {
        final enricher = ExploreFundamentalsEnricher(
          fundamentalsRepository: _FakeCompanyFundamentalsRepository(
            onGetFundamentals: (ticker) async => Right(
              CompanyFundamentals(
                ticker: ticker,
                companyName: 'Apple Inc',
                industry: 'Technology',
                marketCapitalization: 4977637.06,
                peTTM: 38.6073,
                forwardPE: 35.339,
                netMarginTTM: 27.62,
                dividendYieldIndicatedAnnual: 0.50534,
                week52High: 345.34,
                week52Low: 243.42,
                averageVolume10Day: 41.31,
              ),
            ),
          ),
        );

        final result = await enricher.enrich(
          snapshot: Map<String, Object?>.from(baseSnapshot),
        );

        expect(result['fundamentals_status'], 'ok');
        final fundamentals = result['fundamentals'] as Map<String, Object?>;
        final aapl = fundamentals['AAPL'] as Map<String, Object?>;
        expect(aapl['company_name'], 'Apple Inc');
        expect(aapl['industry'], 'Technology');
        expect(aapl['market_capitalization'], 4977637.06);
        expect(aapl['pe_ttm'], 38.6073);
        expect(aapl['forward_pe'], 35.339);
        expect(aapl['net_margin_ttm'], 27.62);
        // Ya viene en % de Finnhub — el enricher no debe re-escalarlo.
        expect(aapl['dividend_yield_indicated_annual'], 0.50534);
        expect(aapl['week_52_high'], 345.34);
        expect(aapl['week_52_low'], 243.42);
        expect(aapl['average_volume_10_day'], 41.31);
        // Campos no provistos por el fake no deben aparecer con null.
        expect(aapl.containsKey('pb'), isFalse);
      },
    );

    test('marks status failed when the repository fails without rethrowing', () async {
      final enricher = ExploreFundamentalsEnricher(
        fundamentalsRepository: _FakeCompanyFundamentalsRepository(
          onGetFundamentals: (_) async => Left(HttpError(code: 'network_error')),
        ),
      );

      final result = await enricher.enrich(
        snapshot: Map<String, Object?>.from(baseSnapshot),
      );

      expect(result['fundamentals_status'], 'failed');
      expect(result['fundamentals'], isEmpty);
      expect(result['mode'], 'explore');
    });
  });
}
