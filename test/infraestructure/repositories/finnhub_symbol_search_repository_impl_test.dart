import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/finnhub_http_client.dart';
import 'package:portfolio_assistant/infraestructure/repositories/finnhub_symbol_search_repository_impl.dart';

void main() {
  group('FinnhubSymbolSearchRepositoryImpl', () {
    test('parses matches from a successful /search response', () async {
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
                data: {
                  'count': 1,
                  'result': [
                    {
                      'symbol': 'AAPL',
                      'description': 'APPLE INC',
                      'displaySymbol': 'AAPL',
                      'type': 'Common Stock',
                    },
                  ],
                },
              ),
            );
          },
        ),
      );

      final repository = FinnhubSymbolSearchRepositoryImpl(
        client: FinnhubHttpClient(dio: dio, apiKey: 'test-key'),
      );

      final result = await repository.search('Apple');
      final matches = result.fold((_) => null, (value) => value);

      expect(matches, isNotNull);
      expect(matches, hasLength(1));
      expect(matches!.first.symbol, 'AAPL');
      expect(matches.first.description, 'APPLE INC');
      expect(matches.first.type, 'Common Stock');
    });

    test('returns Right([]) (not an error) when there are no matches', () async {
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
                data: {'count': 0, 'result': <dynamic>[]},
              ),
            );
          },
        ),
      );

      final repository = FinnhubSymbolSearchRepositoryImpl(
        client: FinnhubHttpClient(dio: dio, apiKey: 'test-key'),
      );

      final result = await repository.search('asdfghjkl');

      expect(result.isRight(), isTrue);
      expect(result.fold((_) => null, (value) => value), isEmpty);
    });

    test('returns Left without throwing on a DioException', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionTimeout,
              ),
            );
          },
        ),
      );

      final repository = FinnhubSymbolSearchRepositoryImpl(
        client: FinnhubHttpClient(dio: dio, apiKey: 'test-key'),
      );

      final result = await repository.search('Apple');

      expect(result.isLeft(), isTrue);
    });

    test('returns Left without throwing when no API key is configured', () async {
      final repository = FinnhubSymbolSearchRepositoryImpl(
        client: FinnhubHttpClient(dio: Dio(), apiKey: ''),
      );

      final result = await repository.search('Apple');

      expect(result.isLeft(), isTrue);
    });
  });
}
