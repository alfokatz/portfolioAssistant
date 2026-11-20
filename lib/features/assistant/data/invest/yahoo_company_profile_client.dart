import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/yahoo_proxy_client.dart';

/// Sector, industria y beta de un ticker según Yahoo Finance.
class YahooCompanyProfile {
  const YahooCompanyProfile({this.sector, this.industry, this.beta});

  final String? sector;
  final String? industry;
  final double? beta;
}

/// Perfil de compañía de CUALQUIER ticker vía Yahoo `quoteSummary`
/// (`assetProfile,summaryDetail`), a través del proxy `yahoo` — sin listas
/// precargadas: el sector y el riesgo salen del dato real, así que Porty
/// puede hablar de cualquier empresa de cualquier industria.
///
/// Antes se pedía directo a Yahoo desde el teléfono, sin la cookie + crumb
/// que Yahoo exige hoy: si respondía 401/429, el sector y la beta llegaban
/// vacíos sin aviso. El proxy arma esa sesión y cachea para todos.
///
/// Nunca lanza: ante 401/red/timeout devuelve `null` para ese ticker.
class YahooCompanyProfileClient {
  YahooCompanyProfileClient({YahooProxyClient? proxy})
    : _proxy = proxy ?? YahooProxyClient();

  final YahooProxyClient _proxy;
  final Map<String, YahooCompanyProfile?> _cache = {};

  // `v8/finance/chart` (precios) no trae el sector de una acción; el sector
  // vive en `assetProfile` y la beta en `summaryDetail`, ambos módulos de
  // `quoteSummary`, que es por símbolo (no admite batch).
  static const _modules = ['assetProfile', 'summaryDetail'];

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
      final result = await _proxy.quoteSummary(
        PortfolioCalculator.toYahooFinanceSymbol(ticker),
        _modules,
      );
      if (result == null) return null;
      final asset = result['assetProfile'];
      final summary = result['summaryDetail'];
      return YahooCompanyProfile(
        sector: asset is Map ? asset['sector'] as String? : null,
        industry: asset is Map ? asset['industry'] as String? : null,
        beta: summary is Map ? YahooProxyClient.number(summary['beta']) : null,
      );
    } catch (_) {
      return null;
    }
  }
}
