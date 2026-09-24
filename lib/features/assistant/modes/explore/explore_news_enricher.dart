import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/repositories/company_news_repository.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/news_query_detector.dart';
import 'package:portfolio_assistant/infraestructure/repositories/finnhub_company_news_repository_impl.dart';

/// Adds [news_sources] and [news_enrichment] to the explore snapshot.
///
/// Fuente: Finnhub `/company-news` (JSON estructurado por ticker). Antes
/// esto llamaba a OpenAI con `web_search` y parseaba texto libre con regex
/// — esa era la causa raíz de resultados inconsistentes: si el modelo
/// cambiaba el formato de su respuesta, el parser perdía fuentes en
/// silencio. Con Finnhub no hay texto que parsear, así que esa clase entera
/// de falla desaparece.
class ExploreNewsEnricher {
  ExploreNewsEnricher({CompanyNewsRepository? newsRepository})
    : _newsRepository = newsRepository ?? FinnhubCompanyNewsRepositoryImpl();

  final CompanyNewsRepository _newsRepository;

  /// [news_enrichment] is one of: `skipped`, `ok`, `empty`, `failed`. A
  /// fifth state, `locked` (user's plan doesn't include news), is NOT set
  /// here — this enricher only ever runs when the caller already confirmed
  /// the user is entitled (see `ExploreContextBuilder.build`'s
  /// `newsAllowed` param, which sets `locked` directly without calling
  /// this class at all).
  Future<Map<String, Object?>> enrich({
    required Map<String, Object?> snapshot,
    required String userMessage,
  }) async {
    if (!isNewsQuery(userMessage)) {
      return {
        ...snapshot,
        'news_sources': <Object?>[],
        'news_enrichment': 'skipped',
      };
    }

    // Lee del ticker ya resuelto por `ExploreContextBuilder` (mención
    // explícita, fallback del turno previo, o nombre de compañía resuelto
    // vía Finnhub `/search`) en vez de re-extraer del texto — antes esto
    // ignoraba cualquier ticker que no viniera literal en este mensaje.
    final exploreTickers = snapshot['explore_tickers'];
    final tickers =
        exploreTickers is Map<String, Object?>
            ? exploreTickers.keys.toList()
            : const <String>[];
    if (tickers.isEmpty) {
      return {
        ...snapshot,
        'news_sources': <Object?>[],
        'news_enrichment': 'empty',
      };
    }

    final items = <CompanyNewsItem>[];
    var anyFailed = false;

    for (final ticker in tickers) {
      // Defensa extra sobre el contrato Either de CompanyNewsRepository: si
      // una implementación del repo llega a lanzar en vez de devolver Left,
      // un ticker con problemas no debe tumbar el resto del snapshot.
      try {
        final result = await _newsRepository.getRecentNews(ticker, limit: 3);
        result.fold((_) => anyFailed = true, items.addAll);
      } catch (_) {
        anyFailed = true;
      }
    }

    if (items.isEmpty) {
      return {
        ...snapshot,
        'news_sources': <Object?>[],
        'news_enrichment': anyFailed ? 'failed' : 'empty',
      };
    }

    items.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    return {
      ...snapshot,
      'news_sources': items.take(3).map(_toJson).toList(),
      'news_enrichment': 'ok',
    };
  }

  Map<String, Object?> _toJson(CompanyNewsItem item) => {
    'ticker': item.ticker,
    'title': item.headline,
    'snippet': item.summary,
    'url': item.url,
    'source': item.source,
    'published_at': item.publishedAt.toIso8601String(),
  };
}
