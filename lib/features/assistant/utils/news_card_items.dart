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

/// Qué notas van en la card de noticias de un resultado de `get_news`.
///
/// Primero las que citó la búsqueda web (`context.sources`, con título
/// propio): son las que respaldan lo que escribe Porty. Después, titulares
/// de la última semana que no estén ya. Antes la card prefería los
/// titulares de GDELT aunque fueran viejos y de otro tema: el texto hablaba
/// de la renuncia de Jensen Huang y la card mostraba el retiro de otra
/// ejecutiva de octubre (2026-11-14). Sin búsqueda web, los titulares como
/// siempre.
///
/// "Fuentes" ([AnswerSources.notShownIn]) no repite lo que la card muestra.
abstract final class NewsCardItems {
  static const max = 3;

  /// Un titular más viejo que esto no acompaña a la búsqueda web.
  static const recent = Duration(days: 7);

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
    final context = result['context'];
    final cited = [
      if (context is Map && context['status'] == 'ok')
        for (final s in _maps(context['sources']))
          if (_isLink(s['url']) && _hasOwnTitle(s))
            NewsCardItem(
              headline: _str(s['title']),
              url: _str(s['url']),
              source: _str(s['source']),
              ticker: tickers.length == 1 ? tickers.first.toUpperCase() : '',
            ),
    ];
    if (cited.isEmpty) return headlines.take(max).toList();

    final asOf = DateTime.tryParse(_str(result['as_of'])) ?? DateTime.now();
    final urls = {for (final c in cited) c.url};
    return [
      ...cited,
      for (final h in headlines)
        if (!urls.contains(h.url) &&
            (h.publishedAt == null ||
                asOf.difference(h.publishedAt!) <= recent))
          h,
    ].take(max).toList();
  }

  /// Las notas como `items` de `QaNewsSummary`, con la fecha relativa a
  /// [asOf] (`dateLabel` lo arma [dateLabel], que pasa quien conoce
  /// `QaTime`).
  static List<Map<String, Object?>> toItems(
    List<NewsCardItem> items, {
    required String Function(DateTime published) dateLabel,
    bool withTicker = false,
  }) => [
    for (final n in items)
      {
        'headline': n.headline,
        'summaryLine': n.summaryLine,
        'dateLabel': n.publishedAt == null ? '' : dateLabel(n.publishedAt!),
        if (n.source.isNotEmpty) 'source': n.source,
        'url': n.url,
        if (withTicker) 'ticker': n.ticker,
      },
  ];

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
