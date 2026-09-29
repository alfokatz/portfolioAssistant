import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/repositories/company_news_repository.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_media_index.dart';
import 'package:portfolio_assistant/features/assistant/data/market/ttl_cache.dart';
import 'package:portfolio_assistant/infraestructure/repositories/finnhub_company_news_repository_impl.dart';

/// Titulares recientes por ticker — Finnhub `/company-news`. Devuelve los 3
/// más recientes entre todos los tickers pedidos.
class NewsFetcher {
  NewsFetcher({
    CompanyNewsRepository? repository,
    Duration? cacheTtl,
    NewsMediaIndex? mediaIndex,
  }) : _repository = repository ?? FinnhubCompanyNewsRepositoryImpl(),
       _cache = TtlCache(cacheTtl ?? const Duration(minutes: 10)),
       _media = mediaIndex ?? NewsMediaIndex.instance;

  static const maxItems = 3;

  final CompanyNewsRepository _repository;
  final TtlCache<List<CompanyNewsItem>> _cache;
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
    items.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    final top = items.take(maxItems).toList();
    top.forEach(_media.record);
    return {'status': 'ok', 'news': top.map(_toJson).toList()};
  }

  Future<List<CompanyNewsItem>?> _forTicker(String ticker) async {
    final cached = _cache.get(ticker);
    if (cached != null) return cached;
    try {
      final result = await _repository.getRecentNews(ticker, limit: maxItems);
      return result.fold<List<CompanyNewsItem>?>((_) => null, (items) {
        _cache.put(ticker, items);
        return items;
      });
    } catch (_) {
      return null;
    }
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
