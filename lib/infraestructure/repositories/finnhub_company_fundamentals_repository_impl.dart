import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_fundamentals.dart';
import 'package:portfolio_assistant/domain/repositories/company_fundamentals_repository.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/finnhub_http_client.dart';

/// Combina `/stock/profile2` (perfil de la compañía) y
/// `/stock/metric?metric=all` (valuación/rentabilidad/dividendo) de Finnhub
/// en un único `CompanyFundamentals` por ticker.
///
/// Nunca lanza: ante red/timeout/401 devuelve `Left(HttpError)`; ante un
/// ticker sin dato en NINGUNO de los dos endpoints (símbolo inválido, o sin
/// cobertura) devuelve `Right(null)` — la misma distinción absence-vs-error
/// que ya usa `FinnhubEarningsCalendarRepositoryImpl`. Si solo uno de los dos
/// endpoints trae datos, igual arma la entidad con los campos del otro en
/// `null` (mejor un fundamentals parcial que ninguno).
class FinnhubCompanyFundamentalsRepositoryImpl
    implements CompanyFundamentalsRepository {
  FinnhubCompanyFundamentalsRepositoryImpl({FinnhubHttpClient? client})
    : _client = client ?? FinnhubHttpClient();

  final FinnhubHttpClient _client;

  @override
  Future<Either<HttpError, CompanyFundamentals?>> getFundamentals(
    String ticker,
  ) async {
    if (!_client.hasApiKey) {
      return Left(
        HttpError(
          code: 'missing_api_key',
          message: 'FINNHUB_API_KEY no configurada',
        ),
      );
    }

    final upperTicker = ticker.toUpperCase();

    try {
      final responses = await Future.wait([
        _client.get('/stock/profile2', queryParameters: {'symbol': upperTicker}),
        _client.get(
          '/stock/metric',
          queryParameters: {'symbol': upperTicker, 'metric': 'all'},
        ),
      ]);

      final profileResponse = responses[0];
      final metricResponse = responses[1];

      if (profileResponse.statusCode != 200 &&
          metricResponse.statusCode != 200) {
        return Left(
          HttpError(
            code: 'finnhub_error_${profileResponse.statusCode}_'
                '${metricResponse.statusCode}',
          ),
        );
      }

      final profile =
          profileResponse.statusCode == 200 && profileResponse.data is Map
              ? (profileResponse.data as Map)
              : const {};
      final metricBody =
          metricResponse.statusCode == 200 && metricResponse.data is Map
              ? (metricResponse.data as Map)
              : const {};
      final metric =
          metricBody['metric'] is Map ? metricBody['metric'] as Map : const {};

      if (profile.isEmpty && metric.isEmpty) {
        return const Right(null);
      }

      return Right(
        CompanyFundamentals(
          ticker: upperTicker,
          companyName: _string(profile['name']),
          industry: _string(profile['finnhubIndustry']),
          exchange: _string(profile['exchange']),
          marketCapitalization: _double(profile['marketCapitalization']),
          sharesOutstanding: _double(profile['shareOutstanding']),
          peTTM: _double(metric['peTTM']),
          forwardPE: _double(metric['forwardPE']),
          pb: _double(metric['pb']),
          psTTM: _double(metric['psTTM']),
          evEbitdaTTM: _double(metric['evEbitdaTTM']),
          pegTTM: _double(metric['pegTTM']),
          beta: _double(metric['beta']),
          roeTTM: _double(metric['roeTTM']),
          roaTTM: _double(metric['roaTTM']),
          grossMarginTTM: _double(metric['grossMarginTTM']),
          operatingMarginTTM: _double(metric['operatingMarginTTM']),
          netMarginTTM: _double(metric['netProfitMarginTTM']),
          epsTTM: _double(metric['epsTTM']),
          epsGrowthTTMYoy: _double(metric['epsGrowthTTMYoy']),
          bookValuePerShareQuarterly: _double(
            metric['bookValuePerShareQuarterly'],
          ),
          revenuePerShareTTM: _double(metric['revenuePerShareTTM']),
          dividendYieldIndicatedAnnual: _double(
            metric['dividendYieldIndicatedAnnual'],
          ),
          dividendPerShareTTM: _double(metric['dividendPerShareTTM']),
          payoutRatioTTM: _double(metric['payoutRatioTTM']),
          week52High: _double(metric['52WeekHigh']),
          week52Low: _double(metric['52WeekLow']),
          week52PriceReturnDaily: _double(metric['52WeekPriceReturnDaily']),
          averageVolume10Day: _double(metric['10DayAverageTradingVolume']),
        ),
      );
    } on DioException catch (e) {
      return Left(HttpError(code: 'network_error', message: e.message));
    } catch (_) {
      return Left(HttpError(code: 'unknown'));
    }
  }

  double? _double(Object? raw) => raw is num ? raw.toDouble() : null;

  String? _string(Object? raw) =>
      raw is String && raw.isNotEmpty ? raw : null;
}
