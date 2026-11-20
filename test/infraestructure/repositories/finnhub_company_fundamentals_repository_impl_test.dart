import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/finnhub_http_client.dart';
import 'package:portfolio_assistant/infraestructure/repositories/finnhub_company_fundamentals_repository_impl.dart';

void main() {
  group('FinnhubCompanyFundamentalsRepositoryImpl', () {
    Dio dioResolving({
      required Map<String, dynamic> profile,
      required Map<String, dynamic> metric,
    }) {
      final dio = Dio(
        BaseOptions(validateStatus: (status) => status != null && status < 500),
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final isProfile = options.path.contains('/stock/profile2');
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: isProfile ? profile : {'metric': metric, 'metricType': 'all'},
              ),
            );
          },
        ),
      );
      return dio;
    }

    test('combines profile2 + metric into one entity', () async {
      final dio = dioResolving(
        profile: {
          'ticker': 'AAPL',
          'name': 'Apple Inc',
          'finnhubIndustry': 'Technology',
          'exchange': 'NASDAQ NMS - GLOBAL MARKET',
          'marketCapitalization': 4977637.06,
          'shareOutstanding': 14687.36,
        },
        metric: {
          'peTTM': 38.6073,
          'forwardPE': 35.33932,
          'pb': 46.295,
          'psTTM': 10.6628,
          'evEbitdaTTM': 29.9028,
          'pegTTM': 2.82268,
          'beta': 1.0948739,
          'roeTTM': 137.18,
          'roaTTM': 34.55,
          'grossMarginTTM': 48.65,
          'operatingMarginTTM': 33.17,
          'netProfitMarginTTM': 27.62,
          'epsTTM': 8.7233,
          'epsGrowthTTMYoy': 32.61,
          'bookValuePerShareQuarterly': 7.3599,
          'revenuePerShareTTM': 31.725,
          'dividendYieldIndicatedAnnual': 0.50534,
          'dividendPerShareTTM': 1.0616,
          'payoutRatioTTM': 12.13,
          '52WeekHigh': 345.34,
          '52WeekLow': 243.42,
          '52WeekPriceReturnDaily': 33.1378,
          '10DayAverageTradingVolume': 41.31066,
        },
      );

      final repository = FinnhubCompanyFundamentalsRepositoryImpl(
        client: FinnhubHttpClient(dio: dio, baseUrl: 'https://proxy.test/finnhub', accessToken: () async => 'jwt'),
      );

      final result = await repository.getFundamentals('AAPL');
      final data = result.fold((_) => null, (value) => value);

      expect(data, isNotNull);
      expect(data!.ticker, 'AAPL');
      expect(data.companyName, 'Apple Inc');
      expect(data.industry, 'Technology');
      expect(data.marketCapitalization, 4977637.06);
      expect(data.sharesOutstanding, 14687.36);
      expect(data.peTTM, 38.6073);
      expect(data.forwardPE, 35.33932);
      // Key mapping regression: Finnhub's field is `netProfitMarginTTM`, not
      // `netMarginTTM` — the entity's own field name differs from the raw key.
      expect(data.netMarginTTM, 27.62);
      expect(data.dividendYieldIndicatedAnnual, 0.50534);
      expect(data.week52High, 345.34);
      expect(data.week52Low, 243.42);
      expect(data.averageVolume10Day, 41.31066);
    });

    test(
      'returns null (not an error) when both endpoints have no data for the ticker',
      () async {
        final dio = dioResolving(profile: {}, metric: {});
        final repository = FinnhubCompanyFundamentalsRepositoryImpl(
          client: FinnhubHttpClient(dio: dio, baseUrl: 'https://proxy.test/finnhub', accessToken: () async => 'jwt'),
        );

        final result = await repository.getFundamentals('ZZZZ');

        expect(result.isRight(), isTrue);
        expect(result.fold((_) => 'left', (value) => value), isNull);
      },
    );

    test(
      'still returns partial data when only one of the two endpoints has data',
      () async {
        final dio = dioResolving(
          profile: {'name': 'Apple Inc', 'finnhubIndustry': 'Technology'},
          metric: {},
        );
        final repository = FinnhubCompanyFundamentalsRepositoryImpl(
          client: FinnhubHttpClient(dio: dio, baseUrl: 'https://proxy.test/finnhub', accessToken: () async => 'jwt'),
        );

        final result = await repository.getFundamentals('AAPL');
        final data = result.fold((_) => null, (value) => value);

        expect(data, isNotNull);
        expect(data!.companyName, 'Apple Inc');
        expect(data.peTTM, isNull);
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

      final repository = FinnhubCompanyFundamentalsRepositoryImpl(
        client: FinnhubHttpClient(dio: dio, baseUrl: 'https://proxy.test/finnhub', accessToken: () async => 'jwt'),
      );

      final result = await repository.getFundamentals('AAPL');

      expect(result.isLeft(), isTrue);
    });

    test('returns Left without throwing when the Finnhub proxy is not configured', () async {
      final repository = FinnhubCompanyFundamentalsRepositoryImpl(
        client: FinnhubHttpClient(dio: Dio(), baseUrl: ''),
      );

      final result = await repository.getFundamentals('AAPL');

      expect(result.isLeft(), isTrue);
    });
  });
}
