import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/sector_display_name.dart';
import 'package:portfolio_assistant/features/assistant/data/market/ttl_cache.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/yahoo_proxy_client.dart';

/// Composición de ETFs y fondos — Yahoo `quoteSummary` (`topHoldings`,
/// `fundProfile`, `quoteType`, `summaryDetail`) vía el proxy `yahoo`.
///
/// Yahoo da las 10 posiciones principales con su peso, el reparto por
/// sector y por clase de activo, no la cartera completa del fondo.
class EtfHoldingsFetcher {
  EtfHoldingsFetcher({YahooProxyClient? proxy, Duration? cacheTtl})
    : _proxy = proxy ?? YahooProxyClient(),
      _cache = TtlCache(cacheTtl ?? const Duration(hours: 6));

  final YahooProxyClient _proxy;
  final TtlCache<Map<String, Object?>> _cache;

  static const _modules = [
    'quoteType',
    'topHoldings',
    'fundProfile',
    'summaryDetail',
  ];

  /// Claves de `sectorWeightings` de Yahoo → nombre que entiende
  /// [SectorDisplayName].
  static const _sectorKeys = {
    'realestate': 'Real Estate',
    'consumer_cyclical': 'Consumer Cyclical',
    'basic_materials': 'Basic Materials',
    'consumer_defensive': 'Consumer Defensive',
    'technology': 'Technology',
    'communication_services': 'Communication Services',
    'financial_services': 'Financial Services',
    'utilities': 'Utilities',
    'industrials': 'Industrials',
    'energy': 'Energy',
    'healthcare': 'Healthcare',
  };

  /// `{status: ok|empty|failed, etfs: {TICKER: {...}}, not_funds: [...]}`.
  /// `not_funds`: tickers que existen pero son acciones (no tienen
  /// composición).
  Future<Map<String, Object?>> fetch(List<String> tickers) async {
    final etfs = <String, Object?>{};
    final notFunds = <String>[];
    var anyFailed = false;

    final results = await Future.wait(tickers.map(_forTicker));
    for (var i = 0; i < tickers.length; i++) {
      final result = results[i];
      if (result == null) {
        anyFailed = true;
      } else if (result['not_a_fund'] == true) {
        notFunds.add(tickers[i]);
      } else if (result.isNotEmpty) {
        etfs[tickers[i]] = result;
      }
    }

    return {
      'status': etfs.isNotEmpty ? 'ok' : (anyFailed ? 'failed' : 'empty'),
      'etfs': etfs,
      if (notFunds.isNotEmpty) 'not_funds': notFunds,
    };
  }

  /// `null` = falló; `{}` = Yahoo no tiene composición para ese ticker.
  Future<Map<String, Object?>?> _forTicker(String ticker) async {
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

  /// Un `result` de quoteSummary → lo que ve el modelo. Porcentajes ya en
  /// % (Yahoo los manda como fracción: 0.0954 → 9.54).
  static Map<String, Object?> parse(Map<String, dynamic> result) {
    final quoteType = _map(result['quoteType']);
    final type = quoteType?['quoteType'] as String?;
    if (type != null && type != 'ETF' && type != 'MUTUALFUND') {
      return {'not_a_fund': true, 'quote_type': type};
    }

    final top = _map(result['topHoldings']);
    final holdings = [
      for (final h in (top?['holdings'] as List? ?? const []))
        if (h is Map && h['symbol'] is String)
          {
            'symbol': h['symbol'],
            if (h['holdingName'] is String) 'name': h['holdingName'],
            'weight_pct': _pct(h['holdingPercent']),
          },
    ];
    final sectors = <Map<String, Object?>>[];
    for (final entry in (top?['sectorWeightings'] as List? ?? const [])) {
      if (entry is! Map) continue;
      for (final MapEntry(:key, :value) in entry.entries) {
        final pct = _pct(value);
        if (pct == null || pct <= 0) continue;
        sectors.add({
          'sector': SectorDisplayName.fromRaw(_sectorKeys[key] ?? '$key'),
          'weight_pct': pct,
        });
      }
    }
    sectors.sort(
      (a, b) => (b['weight_pct']! as double).compareTo(a['weight_pct']! as double),
    );
    if (holdings.isEmpty && sectors.isEmpty) return {};

    final weights = [for (final h in holdings) h['weight_pct'] as double?];
    final profile = _map(result['fundProfile']);
    final fees = _map(profile?['feesExpensesInvestment']);
    final summary = _map(result['summaryDetail']);
    final json = <String, Object?>{};
    void put(String key, Object? value) {
      if (value != null) json[key] = value;
    }

    put('fund_name', quoteType?['longName'] ?? quoteType?['shortName']);
    put('fund_family', profile?['family']);
    put('category', profile?['categoryName']);
    put('expense_ratio_pct', _pct(fees?['annualReportExpenseRatio']));
    put('total_assets_usd', YahooProxyClient.number(summary?['totalAssets']));
    put('top_holdings', holdings);
    if (weights.isNotEmpty && weights.every((w) => w != null)) {
      put('top_holdings_weight_pct', _round(weights.fold(0.0, (a, w) => a + w!)));
    }
    put('sectors', sectors.isEmpty ? null : sectors.take(6).toList());
    put('stock_position_pct', _pct(top?['stockPosition']));
    put('bond_position_pct', _pct(top?['bondPosition']));
    put('cash_position_pct', _pct(top?['cashPosition']));
    return json;
  }

  static Map<String, dynamic>? _map(Object? value) =>
      value is Map<String, dynamic> ? value : null;

  static double? _pct(Object? value) {
    final fraction = YahooProxyClient.number(value);
    return fraction == null ? null : _round(fraction * 100);
  }

  static double _round(double value) => (value * 100).roundToDouble() / 100;
}
