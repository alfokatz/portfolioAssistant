import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/yahoo_company_profile_client.dart';

Dio _dio(Response<dynamic> Function(RequestOptions options) respond) {
  final dio = Dio(
    BaseOptions(validateStatus: (status) => status != null && status < 500),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(respond(options)),
    ),
  );
  return dio;
}

Map<String, dynamic> _quoteSummary(Map<String, dynamic> result) => {
  'quoteSummary': {
    'result': [result],
    'error': null,
  },
};

void main() {
  group('YahooCompanyProfileClient', () {
    test(
      'parses sector, industry and beta for ANY ticker (no fixed list)',
      () async {
        final requested = <Uri>[];
        final client = YahooCompanyProfileClient(
          dio: _dio((options) {
            requested.add(options.uri);
            return Response(
              requestOptions: options,
              statusCode: 200,
              data: _quoteSummary({
                'assetProfile': {
                  'sector': 'Utilities',
                  'industry': 'Utilities—Renewable',
                },
                'summaryDetail': {
                  'beta': {'raw': 0.72, 'fmt': '0.72'},
                },
              }),
            );
          }),
        );

        final profiles = await client.fetchProfiles(['NEE']);

        expect(profiles['NEE']!.sector, 'Utilities');
        expect(profiles['NEE']!.industry, 'Utilities—Renewable');
        expect(profiles['NEE']!.beta, 0.72);
        expect(requested.single.path, endsWith('/quoteSummary/NEE'));
        expect(
          requested.single.queryParameters['modules'],
          'assetProfile,summaryDetail',
        );
      },
    );

    test('returns null on 401 and on network errors, never throws', () async {
      final unauthorized = YahooCompanyProfileClient(
        dio: _dio(
          (options) => Response(
            requestOptions: options,
            statusCode: 401,
            data: <String, dynamic>{},
          ),
        ),
      );
      expect((await unauthorized.fetchProfiles(['GGAL']))['GGAL'], isNull);

      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest:
              (options, handler) => handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionTimeout,
                ),
              ),
        ),
      );
      final offline = YahooCompanyProfileClient(dio: dio);
      expect((await offline.fetchProfiles(['X']))['X'], isNull);
    });

    test('caches successful profiles, retries failed ones', () async {
      var calls = 0;
      var fail = true;
      final client = YahooCompanyProfileClient(
        dio: _dio((options) {
          calls++;
          return fail
              ? Response(requestOptions: options, statusCode: 404, data: {})
              : Response(
                requestOptions: options,
                statusCode: 200,
                data: _quoteSummary({
                  'assetProfile': {'sector': 'Technology'},
                }),
              );
        }),
      );

      expect((await client.fetchProfiles(['AAPL']))['AAPL'], isNull);
      fail = false;
      expect(
        (await client.fetchProfiles(['aapl']))['AAPL']!.sector,
        'Technology',
      );
      await client.fetchProfiles(['AAPL']);
      expect(calls, 2);
    });
  });
}
