import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/symbol_search_result.dart';
import 'package:portfolio_assistant/domain/repositories/symbol_search_repository.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/finnhub_http_client.dart';

/// Nunca lanza: ante red/timeout/401/datos vacíos devuelve `Left`/`Right([])`
/// según corresponda — mismo contrato que `FinnhubCompanyNewsRepositoryImpl`.
class FinnhubSymbolSearchRepositoryImpl implements SymbolSearchRepository {
  FinnhubSymbolSearchRepositoryImpl({FinnhubHttpClient? client})
    : _client = client ?? FinnhubHttpClient();

  final FinnhubHttpClient _client;

  @override
  Future<Either<HttpError, List<SymbolSearchResult>>> search(
    String query,
  ) async {
    if (!_client.hasApiKey) {
      return Left(
        HttpError(
          code: 'missing_api_key',
          message: 'FINNHUB_API_KEY no configurada',
        ),
      );
    }

    try {
      final response = await _client.get(
        '/search',
        queryParameters: {'q': query},
      );

      if (response.statusCode != 200) {
        return Left(HttpError(code: 'finnhub_error_${response.statusCode}'));
      }

      final data = response.data;
      final results = data is Map ? data['result'] : null;
      if (results is! List) return const Right([]);

      return Right(
        results
            .whereType<Map>()
            .map(_parseItem)
            .whereType<SymbolSearchResult>()
            .toList(),
      );
    } on DioException catch (e) {
      return Left(HttpError(code: 'network_error', message: e.message));
    } catch (_) {
      return Left(HttpError(code: 'unknown'));
    }
  }

  SymbolSearchResult? _parseItem(Map raw) {
    final symbol = raw['symbol'] as String?;
    if (symbol == null || symbol.isEmpty) return null;
    return SymbolSearchResult(
      symbol: symbol,
      description: (raw['description'] as String?) ?? '',
      type: (raw['type'] as String?) ?? '',
    );
  }
}
