import 'package:portfolio_assistant/domain/entities/company_fundamentals.dart';
import 'package:portfolio_assistant/domain/repositories/company_fundamentals_repository.dart';
import 'package:portfolio_assistant/features/assistant/data/market/ttl_cache.dart';
import 'package:portfolio_assistant/infraestructure/repositories/finnhub_company_fundamentals_repository_impl.dart';

/// Valuación, rentabilidad y dividendo por ticker — Finnhub `/stock/profile2`
/// + `/stock/metric`.
class FundamentalsFetcher {
  FundamentalsFetcher({
    CompanyFundamentalsRepository? repository,
    Duration? cacheTtl,
  }) : _repository = repository ?? FinnhubCompanyFundamentalsRepositoryImpl(),
       _cache = TtlCache(cacheTtl ?? const Duration(hours: 1));

  final CompanyFundamentalsRepository _repository;
  final TtlCache<Map<String, Object?>> _cache;

  /// `{status: ok|empty|failed, fundamentals: {TICKER: {...}}}`.
  Future<Map<String, Object?>> fetch(List<String> tickers) async {
    final fundamentals = <String, Object?>{};
    var anyFailed = false;

    final results = await Future.wait(tickers.map(_forTicker));
    for (var i = 0; i < tickers.length; i++) {
      final result = results[i];
      if (result == null) {
        anyFailed = true;
      } else if (result.isNotEmpty) {
        fundamentals[tickers[i]] = result;
      }
    }

    return {
      'status':
          fundamentals.isNotEmpty ? 'ok' : (anyFailed ? 'failed' : 'empty'),
      'fundamentals': fundamentals,
    };
  }

  /// `null` = falló; `{}` = Finnhub no tiene datos para ese ticker.
  Future<Map<String, Object?>?> _forTicker(String ticker) async {
    final cached = _cache.get(ticker);
    if (cached != null) return cached;
    try {
      final result = await _repository.getFundamentals(ticker);
      return result.fold<Map<String, Object?>?>((_) => null, (data) {
        final json = data == null ? <String, Object?>{} : _toJson(data);
        _cache.put(ticker, json);
        return json;
      });
    } catch (_) {
      return null;
    }
  }

  static Map<String, Object?> _toJson(CompanyFundamentals f) {
    final json = <String, Object?>{};
    void put(String key, Object? value) {
      if (value != null) json[key] = value;
    }

    put('company_name', f.companyName);
    put('industry', f.industry);
    put('exchange', f.exchange);
    put('market_capitalization', f.marketCapitalization);
    put('shares_outstanding', f.sharesOutstanding);
    put('pe_ttm', f.peTTM);
    put('forward_pe', f.forwardPE);
    put('pb', f.pb);
    put('ps_ttm', f.psTTM);
    put('ev_ebitda_ttm', f.evEbitdaTTM);
    put('peg_ttm', f.pegTTM);
    put('beta', f.beta);
    put('roe_ttm', f.roeTTM);
    put('roa_ttm', f.roaTTM);
    put('gross_margin_ttm', f.grossMarginTTM);
    put('operating_margin_ttm', f.operatingMarginTTM);
    put('net_margin_ttm', f.netMarginTTM);
    put('eps_ttm', f.epsTTM);
    put('eps_growth_ttm_yoy', f.epsGrowthTTMYoy);
    put('book_value_per_share_quarterly', f.bookValuePerShareQuarterly);
    put('revenue_per_share_ttm', f.revenuePerShareTTM);
    put('dividend_yield_indicated_annual', f.dividendYieldIndicatedAnnual);
    put('dividend_per_share_ttm', f.dividendPerShareTTM);
    put('payout_ratio_ttm', f.payoutRatioTTM);
    put('week_52_high', f.week52High);
    put('week_52_low', f.week52Low);
    put('week_52_price_return_daily', f.week52PriceReturnDaily);
    put('average_volume_10_day', f.averageVolume10Day);
    return json;
  }
}
