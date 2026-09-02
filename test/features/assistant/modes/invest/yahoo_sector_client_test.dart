import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/yahoo_sector_client.dart';

void main() {
  group('YahooSectorClient', () {
    test('returns null sectors on 401 without throwing', () async {
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
                statusCode: 401,
                data: <String, dynamic>{},
              ),
            );
          },
        ),
      );

      final client = YahooSectorClient(dio: dio);
      final sectors = await client.fetchSectors(['GGAL', 'YPF']);

      expect(sectors['GGAL'], isNull);
      expect(sectors['YPF'], isNull);
    });

    test('returns null sectors on DioException without throwing', () async {
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

      final client = YahooSectorClient(dio: dio);
      final sectors = await client.fetchSectors(['UNKNOWN']);

      expect(sectors['UNKNOWN'], isNull);
    });

    test('parses sector from a quoteSummary/assetProfile response', () async {
      // Forma real de v10/finance/quoteSummary?modules=assetProfile — v7
      // (probado antes acá) nunca trae `sector` para acciones, que es
      // justamente el bug que este cliente tenía.
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
                data: {
                  'quoteSummary': {
                    'result': [
                      {
                        'assetProfile': {
                          'sector': 'Financial Services',
                          'industry': 'Banks—Regional',
                        },
                      },
                    ],
                    'error': null,
                  },
                },
              ),
            );
          },
        ),
      );

      final client = YahooSectorClient(dio: dio);
      final sectors = await client.fetchSectors(['GGAL']);

      expect(sectors['GGAL'], 'Financial Services');
    });

    test('returns null when quoteSummary has no assetProfile result', () async {
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
                data: {
                  'quoteSummary': {'result': <dynamic>[], 'error': null},
                },
              ),
            );
          },
        ),
      );

      final client = YahooSectorClient(dio: dio);
      final sectors = await client.fetchSectors(['NOSECTOR']);

      expect(sectors['NOSECTOR'], isNull);
    });

    test('resolves each ticker independently within a batch', () async {
      final dio = Dio(
        BaseOptions(
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final symbol = options.path.split('/').last;
            if (symbol == 'AAPL') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'quoteSummary': {
                      'result': [
                        {
                          'assetProfile': {'sector': 'Technology'},
                        },
                      ],
                      'error': null,
                    },
                  },
                ),
              );
            } else {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 404,
                  data: <String, dynamic>{},
                ),
              );
            }
          },
        ),
      );

      final client = YahooSectorClient(dio: dio);
      final sectors = await client.fetchSectors(['AAPL', 'BROKEN']);

      expect(sectors['AAPL'], 'Technology');
      expect(sectors['BROKEN'], isNull);
    });
  });
}
