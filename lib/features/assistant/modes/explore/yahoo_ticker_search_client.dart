import 'package:dio/dio.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/search_query_variants.dart';

/// Resultado de búsqueda de símbolos en Yahoo Finance.
class TickerSearchHit {
  const TickerSearchHit({
    required this.symbol,
    required this.quoteType,
    this.shortName,
    this.score,
  });

  final String symbol;
  final String quoteType;
  final String? shortName;
  final double? score;
}

/// Busca tickers por nombre de empresa en Yahoo Finance Search API.
///
/// Prueba variantes de la consulta y el host query2 (query1 suele devolver 429).
/// Nunca lanza: ante error de red devuelve lista vacía.
class YahooTickerSearchClient {
  YahooTickerSearchClient({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;
  final Map<String, List<TickerSearchHit>> _cache = {};

  static const _searchHosts = [
    'https://query2.finance.yahoo.com/v1/finance/search',
    'https://query1.finance.yahoo.com/v1/finance/search',
  ];

  static const _allowedQuoteTypes = {
    'EQUITY',
    'ETF',
    'MUTUALFUND',
    'INDEX',
  };

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
              'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
              'Mobile/15E148 Safari/604.1',
          'Accept': 'application/json',
        },
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (status) => status != null && status < 500,
      ),
    );
  }

  Future<List<TickerSearchHit>> search(
    String query, {
    int limit = 3,
  }) async {
    for (final variant in SearchQueryVariants.variants(query)) {
      final hits = await _searchSingleQuery(variant, limit: limit);
      if (hits.isNotEmpty) return hits;
    }
    return const [];
  }

  Future<List<TickerSearchHit>> _searchSingleQuery(
    String query, {
    required int limit,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || limit <= 0) return const [];

    final cacheKey = '${trimmed.toLowerCase()}|$limit';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    for (final host in _searchHosts) {
      final hits = await _fetchFromHost(host, trimmed, limit: limit);
      if (hits.isNotEmpty) {
        return _cacheAndReturn(cacheKey, hits);
      }
    }

    return _cacheAndReturn(cacheKey, const []);
  }

  Future<List<TickerSearchHit>> _fetchFromHost(
    String url,
    String query, {
    required int limit,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        url,
        queryParameters: {
          'q': query,
          'quotesCount': limit.clamp(1, 10),
          'newsCount': 0,
          'listsCount': 0,
          'enableFuzzyQuery': true,
        },
      );

      if (response.statusCode != 200) return const [];

      final quotes = response.data?['quotes'];
      if (quotes is! List) return const [];

      final hits = <TickerSearchHit>[];
      for (final item in quotes) {
        if (item is! Map<String, dynamic>) continue;
        final symbol = item['symbol'] as String?;
        final quoteType = item['quoteType'] as String?;
        if (symbol == null || quoteType == null) continue;
        if (!_allowedQuoteTypes.contains(quoteType)) continue;
        if (_isNonUsListing(symbol)) continue;

        hits.add(
          TickerSearchHit(
            symbol: symbol.toUpperCase(),
            quoteType: quoteType,
            shortName:
                item['shortname'] as String? ?? item['longname'] as String?,
            score: (item['score'] as num?)?.toDouble(),
          ),
        );
        if (hits.length >= limit) break;
      }

      return hits;
    } on DioException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  static bool _isNonUsListing(String symbol) => symbol.contains('.');

  List<TickerSearchHit> _cacheAndReturn(
    String cacheKey,
    List<TickerSearchHit> hits,
  ) {
    _cache[cacheKey] = hits;
    return hits;
  }
}
