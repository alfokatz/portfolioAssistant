import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/earnings_surprise.dart';
import 'package:portfolio_assistant/domain/repositories/earnings_history_repository.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/finnhub_http_client.dart';

/// Finnhub `/stock/earnings`: EPS real, estimado y sorpresa de los últimos
/// trimestres (4 en el plan gratuito). Mismo contrato que el resto de los
/// repos Finnhub: nunca lanza.
class FinnhubEarningsHistoryRepositoryImpl
    implements EarningsHistoryRepository {
  FinnhubEarningsHistoryRepositoryImpl({FinnhubHttpClient? client})
    : _client = client ?? FinnhubHttpClient();

  final FinnhubHttpClient _client;

  @override
  Future<Either<HttpError, List<EarningsSurprise>>> getEpsHistory(
    String ticker,
  ) async {
    if (!_client.isConfigured) {
      return Left(
        HttpError(
          code: 'finnhub_unavailable',
          message: 'Proxy de Finnhub no configurado',
        ),
      );
    }

    final upper = ticker.toUpperCase();
    try {
      final response = await _client.get(
        '/stock/earnings',
        queryParameters: {'symbol': upper},
      );
      if (response.statusCode != 200) {
        return Left(HttpError(code: 'finnhub_error_${response.statusCode}'));
      }
      final data = response.data;
      if (data is! List) return const Right([]);

      final items =
          data
              .whereType<Map>()
              .map((raw) => _parse(raw, upper))
              .whereType<EarningsSurprise>()
              .toList()
            ..sort((a, b) => b.period.compareTo(a.period));
      return Right(items);
    } on DioException catch (e) {
      return Left(HttpError(code: 'network_error', message: e.message));
    } catch (_) {
      return Left(HttpError(code: 'unknown'));
    }
  }

  EarningsSurprise? _parse(Map raw, String ticker) {
    final period = DateTime.tryParse('${raw['period']}');
    if (period == null) return null;
    final symbol = raw['symbol'];
    if (symbol is String && symbol.toUpperCase() != ticker) return null;
    return EarningsSurprise(
      ticker: ticker,
      period: period,
      fiscalQuarter: (raw['quarter'] as num?)?.toInt(),
      fiscalYear: (raw['year'] as num?)?.toInt(),
      epsActual: (raw['actual'] as num?)?.toDouble(),
      epsEstimate: (raw['estimate'] as num?)?.toDouble(),
      surprisePercent: (raw['surprisePercent'] as num?)?.toDouble(),
    );
  }
}
