import 'package:portfolio_assistant/domain/entities/company_fundamentals.dart';
import 'package:portfolio_assistant/domain/repositories/company_fundamentals_repository.dart';
import 'package:portfolio_assistant/infraestructure/repositories/finnhub_company_fundamentals_repository_impl.dart';

/// Agrega `fundamentals` y `fundamentals_status` al snapshot de explore para
/// cada ticker ya presente en `explore_tickers`.
///
/// Igual que `ExploreEarningsEnricher`, no se gatea por keywords en el
/// mensaje: una consulta a Finnhub por ticker es barata, así que se trae
/// siempre que haya tickers en el snapshot y es el modelo — vía las reglas
/// de prompt — quien decide si la pregunta amerita mostrar el widget de
/// fundamentals.
class ExploreFundamentalsEnricher {
  ExploreFundamentalsEnricher({
    CompanyFundamentalsRepository? fundamentalsRepository,
  }) : _fundamentalsRepository =
           fundamentalsRepository ?? FinnhubCompanyFundamentalsRepositoryImpl();

  final CompanyFundamentalsRepository _fundamentalsRepository;

  /// [fundamentals_status] es uno de: `ok`, `empty`, `failed`. Un cuarto
  /// estado, `locked` (el plan del usuario no incluye esto), NO se setea
  /// acá — este enricher solo corre cuando el caller ya confirmó que el
  /// usuario tiene acceso (ver el param `fundamentalsAllowed` de
  /// `ExploreContextBuilder.build`, que setea `locked` directamente sin
  /// llamar a esta clase).
  Future<Map<String, Object?>> enrich({
    required Map<String, Object?> snapshot,
  }) async {
    final exploreTickers = snapshot['explore_tickers'];
    final tickers =
        exploreTickers is Map<String, Object?>
            ? exploreTickers.keys
            : const <String>[];

    if (tickers.isEmpty) {
      return {
        ...snapshot,
        'fundamentals': <String, Object?>{},
        'fundamentals_status': 'empty',
      };
    }

    final fundamentals = <String, Object?>{};
    var anyFailed = false;

    for (final ticker in tickers) {
      // Defensa extra sobre el contrato Either de
      // CompanyFundamentalsRepository: si una implementación llega a
      // lanzar en vez de devolver Left, un ticker con problemas no debe
      // tumbar el resto del snapshot.
      try {
        final result = await _fundamentalsRepository.getFundamentals(ticker);
        final data = result.fold((_) {
          anyFailed = true;
          return null;
        }, (value) => value);

        if (data != null) fundamentals[ticker] = _toJson(data);
      } catch (_) {
        anyFailed = true;
      }
    }

    final status =
        fundamentals.isNotEmpty ? 'ok' : (anyFailed ? 'failed' : 'empty');

    return {
      ...snapshot,
      'fundamentals': fundamentals,
      'fundamentals_status': status,
    };
  }

  Map<String, Object?> _toJson(CompanyFundamentals f) {
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
    put(
      'dividend_yield_indicated_annual',
      f.dividendYieldIndicatedAnnual,
    );
    put('dividend_per_share_ttm', f.dividendPerShareTTM);
    put('payout_ratio_ttm', f.payoutRatioTTM);
    put('week_52_high', f.week52High);
    put('week_52_low', f.week52Low);
    put('week_52_price_return_daily', f.week52PriceReturnDaily);
    put('average_volume_10_day', f.averageVolume10Day);
    return json;
  }
}
