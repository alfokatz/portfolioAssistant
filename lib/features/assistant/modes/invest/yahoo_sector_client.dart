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

  static const _quoteUrl = 'https://query1.finance.yahoo.com/v7/finance/quote';

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

    try {
      final symbols = tickers
          .map(PortfolioCalculator.toYahooFinanceSymbol)
          .join(',');
      final response = await _dio.get<Map<String, dynamic>>(
        _quoteUrl,
        queryParameters: {'symbols': symbols},
      );

      if (response.statusCode != 200) {
        return _nullMap(tickers);
      }

      final data = response.data;
      final quoteResponse = data?['quoteResponse'];
      if (quoteResponse is! Map<String, dynamic>) {
        return _nullMap(tickers);
      }

      final results = quoteResponse['result'];
      if (results is! List) {
        return _nullMap(tickers);
      }

      final bySymbol = <String, String?>{};
      for (final item in results) {
        if (item is! Map<String, dynamic>) continue;
        final symbol = item['symbol'] as String?;
        final sector = item['sector'] as String?;
        if (symbol != null) {
          bySymbol[symbol.toUpperCase()] = sector;
        }
      }

      final mapped = <String, String?>{};
      for (final ticker in tickers) {
        final yahooSymbol =
            PortfolioCalculator.toYahooFinanceSymbol(ticker).toUpperCase();
        mapped[ticker] = bySymbol[yahooSymbol] ?? bySymbol[ticker];
      }
      return mapped;
    } on DioException {
      return _nullMap(tickers);
    } catch (_) {
      return _nullMap(tickers);
    }
  }

  static Map<String, String?> _nullMap(List<String> tickers) =>
      {for (final ticker in tickers) ticker: null};
}
