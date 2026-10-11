import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/assistant/data/market/earnings_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/fundamentals_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/ttl_cache.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/porty_edge_client.dart';

/// Resultado de un ticker en la edge function `sec`: el body, o por qué no.
sealed class _SecResult {
  const _SecResult();
}

class _SecOk extends _SecResult {
  const _SecOk(this.body);
  final Map<String, Object?> body;
}

class _SecNotFound extends _SecResult {
  const _SecNotFound();
}

class _SecLocked extends _SecResult {
  const _SecLocked();
}

class _SecFailed extends _SecResult {
  const _SecFailed();
}

Future<_SecResult> _secGet(
  PortyEdgeClient client,
  String endpoint,
  String ticker,
) async {
  final r = await client.get('sec/$endpoint', query: {'ticker': ticker});
  if (r.planRequired) return const _SecLocked();
  if (!r.ok) return const _SecFailed();
  final status = r.body!['status'];
  if (status == 'not_found') return const _SecNotFound();
  if (status != 'ok') return const _SecOk({});
  return _SecOk(r.body!);
}

double? _num(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

double? _round(double? v, [int digits = 2]) =>
    v == null || !v.isFinite ? null : double.parse(v.toStringAsFixed(digits));

String? _dateLabel(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}');
  return d == null ? null : EarningsFetcher.dateLabel(d);
}

/// Junta los resultados por ticker en el formato de las tools:
/// `{status, <key>: {TICKER: {...}}, not_in_sec?: [..], locked_tickers?}`.
Map<String, Object?> _collect(
  String key,
  List<String> tickers,
  List<_SecResult> results,
  Map<String, Object?> Function(Map<String, Object?> body) map,
) {
  final out = <String, Object?>{};
  final notInSec = <String>[];
  final locked = <String>[];
  var anyFailed = false;
  for (var i = 0; i < tickers.length; i++) {
    switch (results[i]) {
      case _SecOk(:final body) when body.isNotEmpty:
        out[tickers[i]] = map(body);
      case _SecOk():
        break;
      case _SecNotFound():
        notInSec.add(tickers[i]);
      case _SecLocked():
        locked.add(tickers[i]);
      case _SecFailed():
        anyFailed = true;
    }
  }
  final status =
      out.isNotEmpty
          ? 'ok'
          : locked.length == tickers.length
          ? 'locked'
          : anyFailed
          ? 'failed'
          : 'empty';
  return {
    'status': status,
    key: out,
    if (notInSec.isNotEmpty) 'not_in_sec': notInSec,
    if (locked.isNotEmpty) ...{
      'locked_tickers': locked,
      'required_plan': 'gold',
    },
  };
}

/// `get_earnings` con SEC EDGAR (`news_provider = v2`): último comunicado de
/// resultados (texto en inglés, recortado, para resumir), EPS e ingresos de
/// los últimos trimestres con su variación interanual, y el próximo reporte
/// ESTIMADO (EDGAR no publica un calendario). Sin consenso de analistas.
class SecEarningsFetcher implements EarningsSource {
  SecEarningsFetcher({PortyEdgeClient? client, Duration? cacheTtl})
    : _client = client ?? PortyEdgeClient(),
      _cache = TtlCache(cacheTtl ?? const Duration(hours: 1));

  final PortyEdgeClient _client;
  final TtlCache<_SecResult> _cache;

  @override
  Future<Map<String, Object?>> fetch(List<String> tickers) async {
    final results = await Future.wait(tickers.map(_forTicker));
    return _collect('earnings', tickers, results, toToolJson);
  }

  Future<_SecResult> _forTicker(String ticker) async {
    final cached = _cache.get(ticker);
    if (cached != null) return cached;
    final result = await _secGet(_client, 'earnings', ticker);
    if (result is! _SecFailed) _cache.put(ticker, result);
    return result;
  }

  /// Body de `sec/earnings` → entrada de `get_earnings` por ticker.
  static Map<String, Object?> toToolJson(Map<String, Object?> body) {
    final quarters = [
      for (final q in (body['quarters'] as List? ?? const []).whereType<Map>())
        {
          if ('${q['label'] ?? ''}'.isNotEmpty)
            'fiscal_period_label': '${q['label']}',
          'period_end': q['end'],
          if (_num(q['eps_diluted']) != null) 'eps_actual': _num(q['eps_diluted']),
          if (_num(q['eps_yoy_pct']) != null) 'eps_yoy_pct': _num(q['eps_yoy_pct']),
          if (_num(q['revenue']) != null)
            'revenue_millions': _round(_num(q['revenue'])! / 1e6, 1),
          if (_num(q['revenue_yoy_pct']) != null)
            'revenue_yoy_pct': _num(q['revenue_yoy_pct']),
          if (_num(q['net_income']) != null)
            'net_income_millions': _round(_num(q['net_income'])! / 1e6, 1),
          if (q['derived'] == true) 'derived_from_annual': true,
        },
    ];
    final years = [
      for (final y in (body['years'] as List? ?? const []).whereType<Map>())
        {
          'fiscal_year': y['fiscal_year'],
          if (_num(y['eps_diluted']) != null) 'eps_actual': _num(y['eps_diluted']),
          if (_num(y['revenue']) != null)
            'revenue_millions': _round(_num(y['revenue'])! / 1e6, 1),
          if (_num(y['net_income']) != null)
            'net_income_millions': _round(_num(y['net_income'])! / 1e6, 1),
        },
    ];
    final next = body['next_report'];
    final release = body['latest_release'];
    final latest = quarters.isNotEmpty ? quarters.last : null;
    return {
      'source': 'SEC EDGAR',
      // Explícito en el dato (no solo en el prompt): sin esto el modelo
      // presentaba el EPS del último trimestre como "lo que esperan los
      // analistas" (visto en evals).
      'analyst_consensus':
          'not_available: no analyst estimates here; never present a past '
          'EPS as expected. For the consensus call get_news with a question.',
      if (body['company_name'] != null) 'company_name': body['company_name'],
      if (body['currency'] != null) 'currency': body['currency'],
      if (next is Map && next['date'] != null)
        'next_report': {
          'date': next['date'],
          'date_label': _dateLabel(next['date']),
          'estimated': true,
        },
      if (latest != null)
        'latest_result': {
          ...latest,
          if (release is Map && release['filed'] != null)
            'report_date_label': _dateLabel(release['filed']),
        },
      if (quarters.length >= 2) 'history': quarters,
      if (quarters.isEmpty && years.isNotEmpty) 'annual': years,
      if (release is Map && '${release['text'] ?? ''}'.isNotEmpty)
        'press_release': {
          'form': release['form'],
          'filed_label': _dateLabel(release['filed']),
          'url': release['url'],
          'text': release['text'],
          if (release['truncated'] == true) 'truncated': true,
        },
      if (body['source'] is Map) 'source_url': (body['source'] as Map)['url'],
    };
  }
}

/// `get_fundamentals` con SEC EDGAR (`news_provider = v2`): lo contable
/// sale de los balances presentados a la SEC; lo que depende del precio
/// (P/E, P/S, P/B, valor de mercado, rendimiento del dividendo) se calcula
/// con el precio actual, y solo si el emisor reporta en USD (en un ADR, el
/// EPS es por acción ordinaria y en su moneda: el cociente no tendría
/// sentido).
class SecFundamentalsFetcher implements FundamentalsSource {
  SecFundamentalsFetcher({
    required QuoteRepository quotes,
    PortyEdgeClient? client,
    Duration? cacheTtl,
  }) : _quotes = quotes,
       _client = client ?? PortyEdgeClient(),
       _cache = TtlCache(cacheTtl ?? const Duration(hours: 1));

  final QuoteRepository _quotes;
  final PortyEdgeClient _client;
  final TtlCache<_SecResult> _cache;

  @override
  Future<Map<String, Object?>> fetch(List<String> tickers) async {
    final results = await Future.wait(tickers.map(_forTicker));
    final prices = await Future.wait(tickers.map(_priceInfo));
    final byTicker = {
      for (var i = 0; i < tickers.length; i++) tickers[i]: prices[i],
    };
    return _collect(
      'fundamentals',
      tickers,
      results,
      (body) => toToolJson(body, byTicker[body['ticker']] ?? const PriceInfo()),
    );
  }

  Future<_SecResult> _forTicker(String ticker) async {
    final cached = _cache.get(ticker);
    if (cached != null) return cached;
    final result = await _secGet(_client, 'fundamentals', ticker);
    if (result is! _SecFailed) _cache.put(ticker, result);
    return result;
  }

  Future<PriceInfo> _priceInfo(String ticker) async {
    try {
      final price = (await _quotes.getCurrentPrice(ticker)).fold<double?>(
        (_) => null,
        (p) => p > 0 ? p : null,
      );
      final candles = (await _quotes.getHistoricalDaily(ticker)).fold(
        (_) => const [],
        (c) => c,
      );
      final since = DateTime.now().subtract(const Duration(days: 365));
      final closes = [
        for (final c in candles)
          if (c.date.isAfter(since) && c.close > 0) c.close,
      ];
      return PriceInfo(
        price: price,
        week52High: closes.isEmpty ? null : closes.reduce((a, b) => a > b ? a : b),
        week52Low: closes.isEmpty ? null : closes.reduce((a, b) => a < b ? a : b),
      );
    } catch (_) {
      return const PriceInfo();
    }
  }

  /// Body de `sec/fundamentals` + precio → entrada de `get_fundamentals`,
  /// con las mismas claves que la fuente legacy donde el dato existe.
  static Map<String, Object?> toToolJson(
    Map<String, Object?> b,
    PriceInfo p,
  ) {
    final usd = b['currency'] == 'USD';
    final price = usd ? p.price : null;
    final shares = _num(b['shares_outstanding']);
    final eps = _num(b['eps_diluted_ttm']);
    final revenue = _num(b['revenue_ttm']);
    final equity = _num(b['equity']);
    final ebitda = _num(b['ebitda_ttm']);
    final debt = _num(b['long_term_debt']);
    final cash = _num(b['cash']);
    final dps = _num(b['dividends_per_share_ttm']);
    final marketCap = price != null && shares != null ? price * shares : null;
    double? ratio(double? num, double? den) =>
        num == null || den == null || den <= 0 ? null : _round(num / den, 1);
    double? millions(double? v) => v == null ? null : _round(v / 1e6, 1);

    final json = <String, Object?>{};
    void put(String key, Object? value) {
      if (value != null) json[key] = value;
    }

    put('source', 'SEC EDGAR');
    put('company_name', b['company_name']);
    put('industry', b['industry']);
    put('currency', b['currency']);
    put('data_period_end', b['ttm_end']);
    put('ttm_basis', b['ttm_basis'] == 'annual' ? 'last_fiscal_year' : 'last_4_quarters');
    put('market_capitalization', millions(marketCap));
    put('shares_outstanding', millions(shares));
    put('pe_ttm', ratio(price, eps));
    put('ps_ttm', ratio(marketCap, revenue));
    put('pb', ratio(marketCap, equity));
    put(
      'ev_ebitda_ttm',
      marketCap == null ? null : ratio(marketCap + (debt ?? 0) - (cash ?? 0), ebitda),
    );
    put('roe_ttm', _num(b['roe_pct']));
    put('roa_ttm', _num(b['roa_pct']));
    put('gross_margin_ttm', _num(b['gross_margin_pct']));
    put('operating_margin_ttm', _num(b['operating_margin_pct']));
    put('net_margin_ttm', _num(b['net_margin_pct']));
    put('eps_ttm', eps);
    put('eps_growth_ttm_yoy', _num(b['eps_growth_yoy_pct']));
    put('revenue_ttm_millions', millions(revenue));
    put('revenue_growth_ttm_yoy', _num(b['revenue_growth_yoy_pct']));
    put('net_income_ttm_millions', millions(_num(b['net_income_ttm'])));
    put('long_term_debt_millions', millions(debt));
    put('cash_millions', millions(cash));
    put('dividend_per_share_ttm', dps);
    if (dps != null && dps > 0) {
      put('dividend_yield_indicated_annual', price == null ? null : _round(dps / price * 100, 2));
      put('payout_ratio_ttm', eps == null || eps <= 0 ? null : _round(dps / eps * 100, 1));
    }
    // El rango de 52 semanas y el precio no dependen de la moneda del balance.
    put('week_52_high', _round(p.week52High));
    put('week_52_low', _round(p.week52Low));
    if (b['source'] is Map) put('source_url', (b['source'] as Map)['url']);
    return json;
  }
}

/// Precio actual y rango de 52 semanas (cierres diarios) de un ticker.
class PriceInfo {
  const PriceInfo({this.price, this.week52High, this.week52Low});

  final double? price;
  final double? week52High;
  final double? week52Low;
}
