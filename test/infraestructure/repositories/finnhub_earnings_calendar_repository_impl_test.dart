import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/finnhub_http_client.dart';
import 'package:portfolio_assistant/infraestructure/repositories/finnhub_earnings_calendar_repository_impl.dart';

void main() {
  group('FinnhubEarningsCalendarRepositoryImpl', () {
    Dio dioResolving(dynamic Function(RequestOptions options) buildData) {
      final dio = Dio(
        BaseOptions(validateStatus: (status) => status != null && status < 500),
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: buildData(options),
              ),
            );
          },
        ),
      );
      return dio;
    }

    test('returns the earliest upcoming report as next earnings date', () async {
      final dio = dioResolving(
        (_) => {
          'earningsCalendar': [
            {
              'symbol': 'NVDA',
              'date': '2027-02-10',
              'quarter': 4,
              'year': 2026,
              'epsEstimate': 1.5,
            },
            {
              'symbol': 'NVDA',
              'date': '2026-11-13',
              'quarter': 3,
              'year': 2026,
              'epsEstimate': 1.36,
            },
          ],
        },
      );

      final repository = FinnhubEarningsCalendarRepositoryImpl(
        client: FinnhubHttpClient(dio: dio, apiKey: 'test-key'),
      );

      final result = await repository.getNextEarningsDate('NVDA');
      final entry = result.fold((_) => null, (value) => value);

      expect(entry, isNotNull);
      expect(entry!.reportDate, DateTime(2026, 11, 13));
      expect(entry.fiscalQuarter, 3);
      expect(entry.fiscalYear, 2026);
    });

    test('returns null (not an error) when there is no upcoming report', () async {
      final dio = dioResolving((_) => {'earningsCalendar': <dynamic>[]});
      final repository = FinnhubEarningsCalendarRepositoryImpl(
        client: FinnhubHttpClient(dio: dio, apiKey: 'test-key'),
      );

      final result = await repository.getNextEarningsDate('NVDA');

      expect(result.isRight(), isTrue);
      expect(result.fold((_) => 'left', (value) => value), isNull);
    });

    test(
      'returns the most recent reported entry with both eps values as latest result',
      () async {
        final dio = dioResolving(
          (_) => {
            'earningsCalendar': [
              {
                'symbol': 'AAPL',
                'date': '2026-04-24',
                'epsActual': 1.4,
                'epsEstimate': 1.35,
              },
              {
                'symbol': 'AAPL',
                'date': '2026-07-24',
                'epsActual': 1.5,
                'epsEstimate': 1.4,
              },
              // Reporte futuro ya listado por Finnhub, todavía sin actual.
              {'symbol': 'AAPL', 'date': '2026-10-24', 'epsEstimate': 1.6},
            ],
          },
        );

        final repository = FinnhubEarningsCalendarRepositoryImpl(
          client: FinnhubHttpClient(dio: dio, apiKey: 'test-key'),
        );

        final result = await repository.getLatestEarningsResult('AAPL');
        final latest = result.fold((_) => null, (value) => value);

        expect(latest, isNotNull);
        expect(latest!.reportDate, DateTime(2026, 7, 24));
        expect(latest.epsActual, 1.5);
        expect(latest.epsEstimate, 1.4);
        expect(latest.beatEstimate, isTrue);
      },
    );

    test('returns Left without throwing on a 401 response', () async {
      final dio = Dio(
        BaseOptions(validateStatus: (status) => status != null && status < 500),
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(requestOptions: options, statusCode: 401, data: {}),
            );
          },
        ),
      );

      final repository = FinnhubEarningsCalendarRepositoryImpl(
        client: FinnhubHttpClient(dio: dio, apiKey: 'test-key'),
      );

      final result = await repository.getNextEarningsDate('NVDA');

      expect(result.isLeft(), isTrue);
    });

    test('returns Left without throwing when no API key is configured', () async {
      final repository = FinnhubEarningsCalendarRepositoryImpl(
        client: FinnhubHttpClient(dio: Dio(), apiKey: ''),
      );

      final result = await repository.getNextEarningsDate('NVDA');

      expect(result.isLeft(), isTrue);
    });
  });
}
