/// Una nota para la card de noticias (`QaNewsSummary`).
class NewsCardItem {
  const NewsCardItem({
    required this.headline,
    required this.url,
    this.summaryLine = '',
    this.source = '',
    this.ticker = '',
    this.publishedAt,
  });

  final String headline;
  final String url;
  final String summaryLine;
  final String source;
  final String ticker;
  final DateTime? publishedAt;
}

/// Qué notas van en la card de noticias de un resultado de `get_news`: los
/// titulares (`news`) y, si no llegó ninguno (la fuente de titulares a
/// veces no responde), las notas que citó la búsqueda web
/// (`context.sources`) con título propio. Antes, sin titulares, esas notas
/// quedaban solo como una lista de "Fuentes" ("CNBC, CNBC, CNBC").
///
/// La lista de "Fuentes" ([AnswerSources]) no repite lo que ya está acá: la
/// cita se sigue viendo y se puede tocar, en la card.
abstract final class NewsCardItems {
  static const max = 3;

  /// [tickers]: los de la llamada (`args.tickers`), para rotular las notas
  /// de la búsqueda web, que no traen ticker.
  static List<NewsCardItem> of(
    Map<String, Object?> result, {
    List<String> tickers = const [],
  }) {
    final headlines = [
      for (final n in _maps(result['news']))
        if (_str(n['title']).isNotEmpty && _isLink(n['url']))
          NewsCardItem(
            headline: _str(n['title']),
            url: _str(n['url']),
            summaryLine: _str(n['snippet']),
            source: _str(n['source']),
            ticker: _str(n['ticker']).toUpperCase(),
            publishedAt: DateTime.tryParse(_str(n['published_at'])),
          ),
    ];
    if (headlines.isNotEmpty) return headlines.take(max).toList();

    final context = result['context'];
    if (context is! Map || context['status'] != 'ok') return const [];
    return [
      for (final s in _maps(context['sources']))
        if (_isLink(s['url']) && _hasOwnTitle(s))
          NewsCardItem(
            headline: _str(s['title']),
            url: _str(s['url']),
            source: _str(s['source']),
            ticker: tickers.length == 1 ? tickers.first.toUpperCase() : '',
          ),
    ].take(max).toList();
  }

  /// Un título que dice algo: no vacío ni el nombre del medio.
  static bool _hasOwnTitle(Map s) {
    final title = _str(s['title']).toLowerCase();
    return title.isNotEmpty && title != _str(s['source']).toLowerCase();
  }

  static bool _isLink(Object? url) => _str(url).startsWith('https://');

  static Iterable<Map> _maps(Object? v) =>
      v is List ? v.whereType<Map>() : const <Map>[];

  static String _str(Object? v) => v == null ? '' : '$v'.trim();
}
