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

    test('parses sector from successful response', () async {
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
                  'quoteResponse': {
                    'result': [
                      {
                        'symbol': 'GGAL',
                        'sector': 'Financial Services',
                      },
                    ],
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
  });
}
