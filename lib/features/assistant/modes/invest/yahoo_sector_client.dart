import 'package:dio/dio.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';

/// Obtiene sectores desde Yahoo Finance quote API.
///
/// Nunca lanza: ante 401/red/timeout devuelve `null` por ticker para que el
/// snapshot siga construyéndose con el mapa estático o "Sin clasificar".
class YahooSectorClient {
  YahooSectorClient({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;
  final Map<String, String?> _cache = {};

  // `v7/finance/quote` (usado antes acá) trae precios/market cap pero NUNCA
  // un campo `sector` para acciones — por eso todo ticker resolvía a
  // "Sin clasificar" incluso en respuestas 200 OK. El sector vive en el
  // módulo `assetProfile` de `quoteSummary`, que es por-símbolo (no admite
  // el `symbols=` batch de v7).
  static const _quoteSummaryBaseUrl =
      'https://query1.finance.yahoo.com/v10/finance/quoteSummary';

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        },
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (status) => status != null && status < 500,
      ),
    );
  }

  Future<String?> fetchSector(String ticker) async {
    final upper = ticker.toUpperCase();
    if (_cache.containsKey(upper)) return _cache[upper];

    final sectors = await fetchSectors([upper]);
    return sectors[upper];
  }

  Future<Map<String, String?>> fetchSectors(List<String> tickers) async {
    final result = <String, String?>{};
    final pending = <String>[];

    for (final ticker in tickers.map((t) => t.toUpperCase()).toSet()) {
      if (_cache.containsKey(ticker)) {
        result[ticker] = _cache[ticker];
      } else {
        pending.add(ticker);
      }
    }

    for (var i = 0; i < pending.length; i += 20) {
      final end = i + 20 > pending.length ? pending.length : i + 20;
      final batch = pending.sublist(i, end);
      final fetched = await _fetchBatch(batch);
      for (final entry in fetched.entries) {
        _cache[entry.key] = entry.value;
        result[entry.key] = entry.value;
      }
    }

    return result;
  }

  Future<Map<String, String?>> _fetchBatch(List<String> tickers) async {
    if (tickers.isEmpty) return {};

    // `assetProfile` es un módulo por-símbolo: no hay forma de pedir varios
    // tickers en una sola request como con v7. Se abanica en paralelo
    // (acotado por el chunk de 20 de `fetchSectors`) y cada uno resuelve su
    // propio error sin tumbar al resto del batch.
    final entries = await Future.wait(
      tickers.map((ticker) async {
        return MapEntry(ticker, await _fetchOne(ticker));
      }),
    );
    return Map.fromEntries(entries);
  }

  Future<String?> _fetchOne(String ticker) async {
    try {
      final symbol = PortfolioCalculator.toYahooFinanceSymbol(ticker);
      final response = await _dio.get<Map<String, dynamic>>(
        '$_quoteSummaryBaseUrl/${Uri.encodeComponent(symbol)}',
        queryParameters: {'modules': 'assetProfile'},
      );

      if (response.statusCode != 200) return null;

      final quoteSummary = response.data?['quoteSummary'];
      if (quoteSummary is! Map<String, dynamic>) return null;

      final results = quoteSummary['result'];
      if (results is! List || results.isEmpty) return null;

      final first = results.first;
      if (first is! Map<String, dynamic>) return null;

      final assetProfile = first['assetProfile'];
      if (assetProfile is! Map<String, dynamic>) return null;

      return assetProfile['sector'] as String?;
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
