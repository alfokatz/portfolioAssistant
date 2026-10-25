import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/yahoo_quote_remote_data_source.dart';

/// Shape real de `v8/finance/chart?range=1d&interval=5m` (recortado),
/// incluidos los `null` que Yahoo intercala en intervalos sin operaciones.
Map<String, Object?> _chart({
  List<Object?> timestamps = const [1790343000, 1790343300, 1790343600],
  List<Object?> closes = const [334.92, null, 335.78],
}) => {
  'chart': {
    'result': [
      {
        'meta': {'symbol': 'AAPL'},
        'timestamp': timestamps,
        'indicators': {
          'quote': [
            {'close': closes},
          ],
        },
      },
    ],
    'error': null,
  },
};

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions) handler;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    lastRequest = options;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('YahooQuoteRemoteDataSource.parseIntradayChart', () {
    test('parses timestamps + closes and skips null intervals', () {
      final candles = YahooQuoteRemoteDataSource.parseIntradayChart(_chart());
      expect(candles.map((c) => c.close), [334.92, 335.78]);
      expect(
        candles.first.date,
        DateTime.fromMillisecondsSinceEpoch(1790343000 * 1000, isUtc: true)
            .toLocal(),
      );
    });

    test('unknown ticker shape (result: null + error) → empty', () {
      final body = {
        'chart': {
          'result': null,
          'error': {'code': 'Not Found', 'description': 'No data found'},
        },
      };
      expect(YahooQuoteRemoteDataSource.parseIntradayChart(body), isEmpty);
    });

    test('any unexpected shape → empty instead of throwing', () {
      for (final body in <Object?>[
        null,
        'not json',
        <String, Object?>{},
        {'chart': {'result': []}},
        {'chart': {'result': [{'timestamp': 'nope'}]}},
        {
          'chart': {
            'result': [
              {'timestamp': [1], 'indicators': {'quote': []}},
            ],
          },
        },
      ]) {
        expect(
          YahooQuoteRemoteDataSource.parseIntradayChart(body),
          isEmpty,
          reason: 'body: $body',
        );
      }
    });
  });

  group('YahooQuoteRemoteDataSource.getIntradayCandles', () {
    YahooQuoteRemoteDataSource sourceWith(_StubAdapter adapter) {
      final dio = Dio()..httpClientAdapter = adapter;
      return YahooQuoteRemoteDataSource(dio: dio, cacheTtl: Duration.zero);
    }

    test('requests range=1d interval=5m for the Yahoo symbol', () async {
      final adapter = _StubAdapter(
        (_) async => ResponseBody.fromString(
          '{"chart":{"result":[{"timestamp":[1,2],"indicators":'
          '{"quote":[{"close":[10.0,11.0]}]}}]}}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );
      final candles = await sourceWith(adapter).getIntradayCandles('BRK.B');

      expect(candles.map((c) => c.close), [10.0, 11.0]);
      expect(adapter.lastRequest!.uri.path, endsWith('/chart/BRK-B'));
      expect(adapter.lastRequest!.uri.queryParameters, {
        'range': '1d',
        'interval': '5m',
      });
    });

    test('HTTP errors (429, 404) are a silent empty result', () async {
      for (final status in [404, 429, 500]) {
        final adapter = _StubAdapter(
          (_) async => ResponseBody.fromString('{}', status),
        );
        expect(
          await sourceWith(adapter).getIntradayCandles('AAPL'),
          isEmpty,
          reason: 'status $status',
        );
      }
    });

    test('network failures are a silent empty result', () async {
      final adapter = _StubAdapter(
        (options) async => throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 6),
          requestOptions: options,
        ),
      );
      expect(await sourceWith(adapter).getIntradayCandles('AAPL'), isEmpty);
    });
  });
}
