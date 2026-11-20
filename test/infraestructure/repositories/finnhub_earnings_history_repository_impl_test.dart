import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/finnhub_http_client.dart';
import 'package:portfolio_assistant/infraestructure/repositories/finnhub_earnings_history_repository_impl.dart';

void main() {
  group('FinnhubEarningsHistoryRepositoryImpl', () {
    FinnhubEarningsHistoryRepositoryImpl repoResolving(
      int status,
      dynamic data, {
      void Function(RequestOptions)? onRequest,
    }) {
      final dio = Dio(BaseOptions(validateStatus: (s) => s != null && s < 500));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            onRequest?.call(options);
            handler.resolve(
              Response(requestOptions: options, statusCode: status, data: data),
            );
          },
        ),
      );
      return FinnhubEarningsHistoryRepositoryImpl(
        client: FinnhubHttpClient(dio: dio, baseUrl: 'https://proxy.test/finnhub', accessToken: () async => 'jwt'),
      );
    }

    test('parses /stock/earnings newest first', () async {
      String? path;
      final repo = repoResolving(200, [
        {
          'actual': 0.27,
          'estimate': 0.41,
          'period': '2026-03-31',
          'quarter': 1,
          'year': 2026,
          'surprisePercent': -34.1,
          'symbol': 'TSLA',
        },
        {
          'actual': 0.40,
          'estimate': 0.43,
          'period': '2026-06-30',
          'quarter': 2,
          'year': 2026,
          'surprisePercent': -6.98,
          'symbol': 'TSLA',
        },
        // Sin period: se descarta, no rompe.
        {'actual': 1, 'estimate': 1, 'symbol': 'TSLA'},
      ], onRequest: (o) => path = o.uri.path);

      final result = await repo.getEpsHistory('tsla');
      final items = result.fold((_) => null, (v) => v)!;

      expect(path, endsWith('/stock/earnings'));
      expect(items, hasLength(2));
      expect(items.first.period, DateTime(2026, 6, 30));
      expect(items.first.fiscalQuarter, 2);
      expect(items.first.epsActual, 0.40);
      expect(items.first.beatEstimate, isFalse);
      expect(items.last.surprisePercent, -34.1);
    });

    test('Right([]) on a non-list body', () async {
      final result = await repoResolving(200, {}).getEpsHistory('X');
      expect(result.fold((_) => null, (v) => v), isEmpty);
    });

    test('Left on 401 and without the proxy configured, never throws', () async {
      expect(
        (await repoResolving(401, {}).getEpsHistory('X')).isLeft(),
        isTrue,
      );
      final noKey = FinnhubEarningsHistoryRepositoryImpl(
        client: FinnhubHttpClient(dio: Dio(), baseUrl: ''),
      );
      expect((await noKey.getEpsHistory('X')).isLeft(), isTrue);
    });
  });
}
