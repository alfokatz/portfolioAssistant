import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/assistant/data/market/ttl_cache.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/yahoo_proxy_client.dart';

/// Dividendos de acciones y ETFs — Yahoo `quoteSummary` (`summaryDetail` +
/// `quoteType`) vía el proxy `yahoo`. A diferencia de Finnhub (que no los
/// trae para ETFs), Yahoo da el rendimiento de fondos (`yield`) y de
/// acciones (`dividendYield`).
class DividendFetcher {
  DividendFetcher({YahooProxyClient? proxy, Duration? cacheTtl})
    : _proxy = proxy ?? YahooProxyClient(),
      _cache = TtlCache(cacheTtl ?? const Duration(hours: 6));

  final YahooProxyClient _proxy;
  final TtlCache<Map<String, Object?>> _cache;

  static const _modules = ['quoteType', 'summaryDetail'];

  static const kindEtf = 'etf';
  static const kindStock = 'stock';
  static const kindOther = 'other';

  /// `{status: ok|empty|failed, tickers: {TICKER: {...}}}`. Un ticker sin
  /// datos en Yahoo queda con `status: empty`; uno que falló, `failed`.
  Future<Map<String, Object?>> fetch(List<String> tickers) async {
    final results = await Future.wait(tickers.map(forTicker));
    final byTicker = <String, Object?>{};
    var ok = 0;
    var failed = 0;
    for (var i = 0; i < tickers.length; i++) {
      final r = results[i];
      if (r == null) {
        failed++;
        byTicker[tickers[i]] = const {'status': 'failed'};
      } else if (r.isEmpty) {
        byTicker[tickers[i]] = const {'status': 'empty'};
      } else {
        ok++;
        byTicker[tickers[i]] = r;
      }
    }
    return {
      'status': ok > 0 ? 'ok' : (failed > 0 ? 'failed' : 'empty'),
      'tickers': byTicker,
    };
  }

  /// `null` = falló; `{}` = Yahoo no conoce el ticker.
  Future<Map<String, Object?>?> forTicker(String ticker) async {
    final cached = _cache.get(ticker);
    if (cached != null) return cached;
    try {
      final result = await _proxy.quoteSummary(
        PortfolioCalculator.toYahooFinanceSymbol(ticker),
        _modules,
      );
      final json = result == null ? <String, Object?>{} : parse(result);
      _cache.put(ticker, json);
      return json;
    } catch (_) {
      return null;
    }
  }

  /// Un `result` de quoteSummary → lo que ve el modelo. Porcentajes en %
  /// (Yahoo los manda como fracción: 0.0354 → 3.54). Sin dividendos, el
  /// rendimiento queda en 0 (es un dato: "no paga"), no se omite.
  static Map<String, Object?> parse(Map<String, dynamic> result) {
    final quoteType = _map(result['quoteType']);
    final summary = _map(result['summaryDetail']);
    if (quoteType == null && summary == null) return {};
    final type = '${quoteType?['quoteType'] ?? ''}'.toUpperCase();
    final kind = switch (type) {
      'ETF' || 'MUTUALFUND' => kindEtf,
      'EQUITY' => kindStock,
      _ => kindOther,
    };
    final n = YahooProxyClient.number;
    // ETFs: `yield` (distribuciones de los últimos 12 meses); acciones:
    // `dividendYield` (el dividendo anual indicado sobre el precio).
    final yieldFraction =
        n(summary?['dividendYield']) ??
        n(summary?['yield']) ??
        n(summary?['trailingAnnualDividendYield']);
    final json = <String, Object?>{'status': 'ok', 'kind': kind};
    void put(String key, Object? value) {
      if (value != null) json[key] = value;
    }

    put('name', quoteType?['longName'] ?? quoteType?['shortName']);
    put('price', n(summary?['previousClose']));
    put(
      'dividend_yield_pct',
      yieldFraction == null
          ? (summary == null ? null : 0.0)
          : _pct(yieldFraction),
    );
    put(
      'dividend_per_share_annual',
      n(summary?['dividendRate']) ?? n(summary?['trailingAnnualDividendRate']),
    );
    put('payout_ratio_pct', _optionalPct(summary?['payoutRatio']));
    put(
      'five_year_avg_yield_pct',
      n(summary?['fiveYearAvgDividendYield']), // Yahoo ya lo manda en %.
    );
    final exDate = n(summary?['exDividendDate']);
    if (exDate != null && exDate > 0) {
      final d = DateTime.fromMillisecondsSinceEpoch(
        exDate.toInt() * 1000,
        isUtc: true,
      );
      put(
        'ex_dividend_date',
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}',
      );
    }
    return json;
  }

  static Map<String, dynamic>? _map(Object? value) =>
      value is Map<String, dynamic> ? value : null;

  static double _pct(double fraction) =>
      (fraction * 10000).roundToDouble() / 100;

  static double? _optionalPct(Object? value) {
    final f = YahooProxyClient.number(value);
    return f == null || f <= 0 ? null : _pct(f);
  }
}
