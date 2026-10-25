import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/finnhub_http_client.dart';
import 'package:portfolio_assistant/infraestructure/repositories/finnhub_company_news_repository_impl.dart';

void main() {
  group('FinnhubCompanyNewsRepositoryImpl', () {
    test(
      'parses and sorts recent news, newest first, capped at limit',
      () async {
        final dio = Dio(
          BaseOptions(
            validateStatus: (status) => status != null && status < 500,
          ),
        );
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: [
                    {
                      'headline': 'Older story',
                      'summary': 'An older summary.',
                      'url': 'https://example.com/old',
                      'source': 'Wire A',
                      'datetime': 1700000000,
                      'image': '',
                    },
                    {
                      'headline': 'Newest story',
                      'summary': 'A fresh summary.',
                      'url': 'https://example.com/new',
                      'source': 'Wire B',
                      'datetime': 1750000000,
                      'image': 'https://example.com/new.jpg',
                    },
                  ],
                ),
              );
            },
          ),
        );

        final repository = FinnhubCompanyNewsRepositoryImpl(
          client: FinnhubHttpClient(dio: dio, baseUrl: 'https://proxy.test/finnhub', accessToken: () async => 'jwt'),
        );

        final result = await repository.getRecentNews('AAPL', limit: 3);
        final items = result.fold((_) => null, (value) => value);

        expect(items, isNotNull);
        expect(items, hasLength(2));
        expect(items!.first.headline, 'Newest story');
        expect(items.first.ticker, 'AAPL');
        expect(items.last.headline, 'Older story');
        // Imagen: https se conserva; "" (Finnhub sin imagen) queda en null.
        expect(items.first.imageUrl, 'https://example.com/new.jpg');
        expect(items.last.imageUrl, isNull);
      },
    );

    test(
      'returns Right([]) (not an error) when there are no articles',
      () async {
        final dio = Dio(
          BaseOptions(
            validateStatus: (status) => status != null && status < 500,
          ),
        );
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: <dynamic>[],
                ),
              );
            },
          ),
        );

        final repository = FinnhubCompanyNewsRepositoryImpl(
          client: FinnhubHttpClient(dio: dio, baseUrl: 'https://proxy.test/finnhub', accessToken: () async => 'jwt'),
        );

        final result = await repository.getRecentNews('NVDA');

        expect(result.isRight(), isTrue);
        expect(result.fold((_) => null, (value) => value), isEmpty);
      },
    );

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

      final repository = FinnhubCompanyNewsRepositoryImpl(
        client: FinnhubHttpClient(dio: dio, baseUrl: 'https://proxy.test/finnhub', accessToken: () async => 'jwt'),
      );

      final result = await repository.getRecentNews('NVDA');

      expect(result.isLeft(), isTrue);
    });

    test(
      'returns Left without throwing when the Finnhub proxy is not configured',
      () async {
        final repository = FinnhubCompanyNewsRepositoryImpl(
          client: FinnhubHttpClient(dio: Dio(), baseUrl: ''),
        );

        final result = await repository.getRecentNews('NVDA');

        expect(result.isLeft(), isTrue);
      },
    );
  });
}
