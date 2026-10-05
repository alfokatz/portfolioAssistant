import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/yahoo_company_profile_client.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/yahoo_proxy_client.dart';

Dio _dio(Response<dynamic> Function(RequestOptions options) respond) {
  final dio = Dio(
    BaseOptions(validateStatus: (status) => status != null && status < 600),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(respond(options)),
    ),
  );
  return dio;
}

YahooProxyClient _proxy(Dio dio) => YahooProxyClient(
  dio: dio,
  baseUrl: 'https://proxy.test/functions/v1/yahoo',
  accessToken: () async => 'user-jwt',
  anonKey: 'anon',
);

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
        final requested = <RequestOptions>[];
        final client = YahooCompanyProfileClient(
          proxy: _proxy(_dio((options) {
            requested.add(options);
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
          })),
        );

        final profiles = await client.fetchProfiles(['NEE']);

        expect(profiles['NEE']!.sector, 'Utilities');
        expect(profiles['NEE']!.industry, 'Utilities—Renewable');
        expect(profiles['NEE']!.beta, 0.72);
        // Va al proxy `yahoo` (que arma cookie + crumb), con el JWT del
        // usuario — nunca directo a Yahoo.
        final sent = requested.single;
        expect(sent.uri.host, 'proxy.test');
        expect(sent.uri.path, '/functions/v1/yahoo/quote-summary');
        expect(sent.uri.queryParameters['symbol'], 'NEE');
        expect(
          sent.uri.queryParameters['modules'],
          'assetProfile,summaryDetail',
        );
        expect(sent.headers['Authorization'], 'Bearer user-jwt');
      },
    );

    test('returns null on proxy errors and on network errors, never throws', () async {
      final unauthorized = YahooCompanyProfileClient(
        proxy: _proxy(_dio(
          (options) => Response(
            requestOptions: options,
            statusCode: 401,
            data: <String, dynamic>{},
          ),
        )),
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
      final offline = YahooCompanyProfileClient(proxy: _proxy(dio));
      expect((await offline.fetchProfiles(['X']))['X'], isNull);
    });

    test('caches successful profiles, retries failed ones', () async {
      var calls = 0;
      var fail = true;
      final client = YahooCompanyProfileClient(
        proxy: _proxy(_dio((options) {
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
        })),
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
