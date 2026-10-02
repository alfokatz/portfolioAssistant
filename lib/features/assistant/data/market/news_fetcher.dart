import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/repositories/company_brand_repository.dart';
import 'package:portfolio_assistant/domain/repositories/company_news_repository.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_media_index.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_relevance_ranker.dart';
import 'package:portfolio_assistant/features/assistant/data/market/ttl_cache.dart';
import 'package:portfolio_assistant/infraestructure/repositories/finnhub_company_brand_repository_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/finnhub_company_news_repository_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/google_news_rss_repository_impl.dart';

/// Titulares relevantes por ticker. Fuente principal: Google News RSS
/// (gratis, medios de primera línea, ya ordenado por relevancia); si falla
/// o no trae nada, Finnhub `/company-news`. En ambos casos el resultado
/// pasa por [NewsRelevanceRanker] (menciona a la compañía, medio
/// reconocido, frescura, un solo titular por hecho). Con varios tickers se
/// intercalan, para que ninguno se quede sin titulares.
class NewsFetcher {
  /// [repository] reemplaza a AMBAS fuentes (tests): una sola, sin fallback.
  NewsFetcher({
    CompanyNewsRepository? repository,
    CompanyBrandRepository? brandRepository,
    Duration? cacheTtl,
    NewsMediaIndex? mediaIndex,
  }) : _brands =
           brandRepository ??
           (repository == null ? FinnhubCompanyBrandRepositoryImpl() : null),
       _cache = TtlCache(cacheTtl ?? const Duration(minutes: 10)),
       _names = TtlCache(const Duration(hours: 24)),
       _media = mediaIndex ?? NewsMediaIndex.instance {
    if (repository != null) {
      _primary = repository;
      _fallback = null;
      _primaryIsRanked = false;
    } else {
      _primary = GoogleNewsRssRepositoryImpl(companyNameOf: _companyName);
      _fallback = FinnhubCompanyNewsRepositoryImpl();
      _primaryIsRanked = true;
    }
  }

  static const maxItems = 3;

  /// Cuánto del feed crudo se evalúa por ticker. Finnhub devuelve todo el
  /// rango de fechas en una sola respuesta; esto solo acota el trabajo.
  static const _candidatePool = 250;

  late final CompanyNewsRepository _primary;
  late final CompanyNewsRepository? _fallback;
  late final bool _primaryIsRanked;
  final CompanyBrandRepository? _brands;
  final TtlCache<List<CompanyNewsItem>> _cache;
  final TtlCache<String> _names;
  final NewsMediaIndex _media;

  /// `{status: ok|empty|failed, news: [{ticker, title, snippet, url, source,
  /// published_at}]}`. La imagen de cada artículo NO va en la salida: queda
  /// en [NewsMediaIndex] para que la card la busque por `url`.
  Future<Map<String, Object?>> fetch(List<String> tickers) async {
    final perTicker = await Future.wait(tickers.map(_forTicker));
    final items = <CompanyNewsItem>[];
    var anyFailed = false;
    for (final list in perTicker) {
      if (list == null) {
        anyFailed = true;
      } else {
        items.addAll(list);
      }
    }

    if (items.isEmpty) {
      return {'status': anyFailed ? 'failed' : 'empty', 'news': const []};
    }
    // Intercalado: el mejor de cada ticker, después el segundo de cada uno…
    final top = <CompanyNewsItem>[];
    for (var rank = 0; top.length < maxItems; rank++) {
      var added = false;
      for (final list in perTicker) {
        if (list == null || rank >= list.length) continue;
        top.add(list[rank]);
        added = true;
        if (top.length >= maxItems) break;
      }
      if (!added) break;
    }
    top.forEach(_media.record);
    return {'status': 'ok', 'news': top.map(_toJson).toList()};
  }

  /// Los mejores [perTicker] titulares de cada ticker publicados en
  /// `[from, to)`, ya rankeados (mismo criterio que [fetch]). `null` en un
  /// ticker = las dos fuentes fallaron; lista vacía = no hubo noticias.
  /// Lo usa el informe semanal: una semana cerrada, aunque se genere días
  /// después.
  Future<Map<String, List<CompanyNewsItem>?>> fetchWindow(
    List<String> tickers, {
    required DateTime from,
    required DateTime to,
    int perTicker = 2,
  }) async {
    final lists = await Future.wait(
      tickers.map((t) => _forTicker(t, window: (from: from, to: to))),
    );
    return {
      for (var i = 0; i < tickers.length; i++)
        tickers[i]: lists[i]?.take(perTicker).toList(),
    };
  }

  Future<List<CompanyNewsItem>?> _forTicker(
    String ticker, {
    ({DateTime from, DateTime to})? window,
  }) async {
    final cacheKey =
        window == null
            ? ticker
            : '$ticker|${window.from.toIso8601String()}|'
                '${window.to.toIso8601String()}';
    final cached = _cache.get(cacheKey);
    if (cached != null) return cached;
    try {
      final name = await _companyName(ticker);
      var ranked = await _rankedFrom(
        _primary,
        ticker,
        name,
        feedIsRanked: _primaryIsRanked,
        window: window,
      );
      final fallback = _fallback;
      if ((ranked == null || ranked.isEmpty) && fallback != null) {
        final second = await _rankedFrom(
          fallback,
          ticker,
          name,
          window: window,
        );
        // Falla la principal y el fallback no tiene nada → sigue siendo un
        // "empty" honesto, no un "failed".
        if (second != null) ranked = second;
      }
      if (ranked != null) _cache.put(cacheKey, ranked);
      return ranked;
    } catch (_) {
      return null;
    }
  }

  Future<List<CompanyNewsItem>?> _rankedFrom(
    CompanyNewsRepository repository,
    String ticker,
    String? name, {
    bool feedIsRanked = false,
    ({DateTime from, DateTime to})? window,
  }) async {
    final result = await repository.getRecentNews(
      ticker,
      limit: _candidatePool,
      from: window?.from,
      to: window?.to,
    );
    return result.fold<List<CompanyNewsItem>?>(
      (_) => null,
      (raw) => NewsRelevanceRanker.rank(
        raw,
        ticker: ticker,
        companyName: name,
        limit: maxItems,
        // En una semana cerrada la frescura se mide contra su final: si no,
        // las notas del lunes pierden contra las del viernes solo por fecha.
        now: window?.to.toUtc(),
        feedIsRanked: feedIsRanked,
      ),
    );
  }

  /// Nombre de la compañía de [ticker] (cacheado 24 h). Lo usa también el
  /// informe semanal para reconocer menciones en otros titulares.
  Future<String?> companyName(String ticker) => _companyName(ticker);

  /// Nombre de la compañía para reconocer menciones ("Nvidia" en un
  /// titular de NVDA). Falla → `null` y el ranker usa solo el ticker.
  Future<String?> _companyName(String ticker) async {
    final cached = _names.get(ticker);
    if (cached != null) return cached;
    final brand = await _brands?.getBrand(ticker);
    final name = brand?.name;
    if (name != null) _names.put(ticker, name);
    return name;
  }

  static Map<String, Object?> _toJson(CompanyNewsItem item) => {
    'ticker': item.ticker,
    'title': item.headline,
    'snippet': item.summary,
    'url': item.url,
    'source': item.source,
    'published_at': item.publishedAt.toIso8601String(),
  };
}
