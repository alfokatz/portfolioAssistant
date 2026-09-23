import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/earnings_calendar_entry.dart';
import 'package:portfolio_assistant/domain/entities/earnings_report_result.dart';
import 'package:portfolio_assistant/domain/repositories/earnings_calendar_repository.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_earnings_enricher.dart';

class _FakeEarningsCalendarRepository implements EarningsCalendarRepository {
  _FakeEarningsCalendarRepository({
    this.onGetNextEarningsDate,
    this.onGetLatestEarningsResult,
  });

  final Future<Either<HttpError, EarningsCalendarEntry?>> Function(String)?
  onGetNextEarningsDate;
  final Future<Either<HttpError, EarningsReportResult?>> Function(String)?
  onGetLatestEarningsResult;

  @override
  Future<Either<HttpError, EarningsCalendarEntry?>> getNextEarningsDate(
    String ticker,
  ) {
    return onGetNextEarningsDate?.call(ticker) ??
        Future.value(const Right(null));
  }

  @override
  Future<Either<HttpError, EarningsReportResult?>> getLatestEarningsResult(
    String ticker,
  ) {
    return onGetLatestEarningsResult?.call(ticker) ??
        Future.value(const Right(null));
  }
}

void main() {
  group('ExploreEarningsEnricher', () {
    const baseSnapshot = <String, Object?>{
      'mode': 'explore',
      'explore_tickers': {
        'NVDA': {'fetch_ok': true},
      },
    };

    test('marks status empty when there are no tickers in the snapshot', () async {
      final enricher = ExploreEarningsEnricher(
        earningsRepository: _FakeEarningsCalendarRepository(),
      );

      final result = await enricher.enrich(
        snapshot: const {'mode': 'explore', 'explore_tickers': <String, Object?>{}},
      );

      expect(result['earnings_calendar_status'], 'empty');
      expect(result['earnings_calendar'], isEmpty);
    });

    test('adds next_report when the repository has a scheduled date', () async {
      final enricher = ExploreEarningsEnricher(
        earningsRepository: _FakeEarningsCalendarRepository(
          onGetNextEarningsDate: (ticker) async => Right(
            EarningsCalendarEntry(
              ticker: ticker,
              reportDate: DateTime(2026, 11, 13),
              fiscalQuarter: 3,
              fiscalYear: 2026,
            ),
          ),
        ),
      );

      final result = await enricher.enrich(
        snapshot: Map<String, Object?>.from(baseSnapshot),
      );

      expect(result['earnings_calendar_status'], 'ok');
      final calendar = result['earnings_calendar'] as Map<String, Object?>;
      final nvda = calendar['NVDA'] as Map<String, Object?>;
      final next = nvda['next_report'] as Map<String, Object?>;
      expect(next['date_label'], '13 nov 2026');
      expect(next['fiscal_period_label'], 'T3 FY26');
    });

    // Fallback honesto: la API respondió bien (Right(null)) pero no hay
    // reporte próximo ni resultado publicado para el ticker.
    test('marks status empty when repository responds with no data', () async {
      final enricher = ExploreEarningsEnricher(
        earningsRepository: _FakeEarningsCalendarRepository(),
      );

      final result = await enricher.enrich(
        snapshot: Map<String, Object?>.from(baseSnapshot),
      );

      expect(result['earnings_calendar_status'], 'empty');
      expect(result['earnings_calendar'], isEmpty);
    });

    test('marks status failed when the repository fails without rethrowing', () async {
      final enricher = ExploreEarningsEnricher(
        earningsRepository: _FakeEarningsCalendarRepository(
          onGetNextEarningsDate: (_) async =>
              Left(HttpError(code: 'network_error')),
          onGetLatestEarningsResult: (_) async =>
              Left(HttpError(code: 'network_error')),
        ),
      );

      final result = await enricher.enrich(
        snapshot: Map<String, Object?>.from(baseSnapshot),
      );

      expect(result['earnings_calendar_status'], 'failed');
      expect(result['earnings_calendar'], isEmpty);
      expect(result['mode'], 'explore');
    });

    test(
      'omits latest_result when eps_actual has not been published yet',
      () async {
        final enricher = ExploreEarningsEnricher(
          earningsRepository: _FakeEarningsCalendarRepository(
            onGetLatestEarningsResult: (ticker) async => Right(
              EarningsReportResult(
                ticker: ticker,
                reportDate: DateTime(2026, 11, 13),
                epsEstimate: 1.36,
              ),
            ),
          ),
        );

        final result = await enricher.enrich(
          snapshot: Map<String, Object?>.from(baseSnapshot),
        );

        expect(result['earnings_calendar_status'], 'empty');
        expect(result['earnings_calendar'], isEmpty);
      },
    );
  });
}
