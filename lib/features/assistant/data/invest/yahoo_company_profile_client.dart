import 'package:dio/dio.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';

/// Sector, industria y beta de un ticker según Yahoo Finance.
class YahooCompanyProfile {
  const YahooCompanyProfile({this.sector, this.industry, this.beta});

  final String? sector;
  final String? industry;
  final double? beta;
}

/// Perfil de compañía de CUALQUIER ticker vía Yahoo
/// `v10/finance/quoteSummary?modules=assetProfile,summaryDetail` — sin
/// listas precargadas: el sector y el riesgo salen del dato real, así que
/// Porty puede hablar de cualquier empresa de cualquier industria.
///
/// Nunca lanza: ante 401/red/timeout devuelve `null` para ese ticker.
class YahooCompanyProfileClient {
  YahooCompanyProfileClient({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;
  final Map<String, YahooCompanyProfile?> _cache = {};

  // `v7/finance/quote` trae precios pero NUNCA el sector de una acción; el
  // sector vive en `assetProfile` y la beta en `summaryDetail`, ambos
  // módulos de `quoteSummary`, que es por símbolo (no admite batch).
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

  Future<Map<String, YahooCompanyProfile?>> fetchProfiles(
    Iterable<String> tickers,
  ) async {
    final result = <String, YahooCompanyProfile?>{};
    final pending = <String>[];
    for (final ticker in tickers.map((t) => t.toUpperCase()).toSet()) {
      if (_cache.containsKey(ticker)) {
        result[ticker] = _cache[ticker];
      } else {
        pending.add(ticker);
      }
    }

    // En paralelo, en tandas de 20 para no abrir demasiadas conexiones.
    for (var i = 0; i < pending.length; i += 20) {
      final batch = pending.sublist(
        i,
        i + 20 > pending.length ? pending.length : i + 20,
      );
      final fetched = await Future.wait(batch.map(_fetchOne));
      for (var j = 0; j < batch.length; j++) {
        // Solo se cachea lo que llegó: una falla de red se reintenta en el
        // próximo turno en vez de quedar "sin clasificar" para siempre.
        if (fetched[j] != null) _cache[batch[j]] = fetched[j];
        result[batch[j]] = fetched[j];
      }
    }
    return result;
  }

  Future<YahooCompanyProfile?> _fetchOne(String ticker) async {
    try {
      final symbol = PortfolioCalculator.toYahooFinanceSymbol(ticker);
      final response = await _dio.get<Map<String, dynamic>>(
        '$_quoteSummaryBaseUrl/${Uri.encodeComponent(symbol)}',
        queryParameters: {'modules': 'assetProfile,summaryDetail'},
      );
      if (response.statusCode != 200) return null;

      final quoteSummary = response.data?['quoteSummary'];
      if (quoteSummary is! Map<String, dynamic>) return null;
      final results = quoteSummary['result'];
      if (results is! List || results.isEmpty) return null;
      final first = results.first;
      if (first is! Map<String, dynamic>) return null;

      final asset = first['assetProfile'];
      final summary = first['summaryDetail'];
      final beta = summary is Map ? summary['beta'] : null;
      return YahooCompanyProfile(
        sector: asset is Map ? asset['sector'] as String? : null,
        industry: asset is Map ? asset['industry'] as String? : null,
        // Yahoo manda los números como {"raw": 1.2, "fmt": "1.20"}.
        beta: switch (beta) {
          {'raw': final num raw} => raw.toDouble(),
          final num raw => raw.toDouble(),
          _ => null,
        },
      );
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
