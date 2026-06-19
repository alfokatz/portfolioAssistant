import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/yahoo_ticker_search_client.dart';

void main() {
  group('YahooTickerSearchClient', () {
    test('tries query variants until one returns hits', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final q = options.queryParameters['q'] as String?;
            if (q == 'takes two') {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const {'quotes': []},
                ),
              );
              return;
            }
            if (q == 'take two') {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'quotes': [
                      {
                        'symbol': 'TTWO',
                        'quoteType': 'EQUITY',
                        'shortname': 'Take-Two Interactive Software, Inc.',
                      },
                    ],
                  },
                ),
              );
              return;
            }
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {'quotes': []},
              ),
            );
          },
        ),
      );

      final client = YahooTickerSearchClient(dio: dio);
      final hits = await client.search('takes two');

      expect(hits, hasLength(1));
      expect(hits.first.symbol, 'TTWO');
    });

    test('returns empty list on network failure', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
          },
        ),
      );

      final client = YahooTickerSearchClient(dio: dio);
      final hits = await client.search('apple');

      expect(hits, isEmpty);
    });
  });
}
