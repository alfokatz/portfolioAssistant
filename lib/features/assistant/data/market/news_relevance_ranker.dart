import 'package:portfolio_assistant/domain/entities/company_news_item.dart';

/// Elige los titulares que valen la pena entre lo que devuelve un feed de
/// noticias por ticker.
///
/// Finnhub `/company-news` (plan gratuito) trae ~250 artículos por semana
/// para un ticker grande, ~85% sindicados desde Yahoo, y más de la mitad ni
/// siquiera nombra a la compañía ("Want $1,000 a Month in Passive
/// Income?" aparece etiquetado como NVDA). Ordenar solo por fecha, como se
/// hacía, mostraba justamente esos. Acá:
/// 1. se descarta lo que no menciona a la compañía ni al ticker;
/// 2. se puntúa: mención en el titular > en el resumen, medio reconocido,
///    y frescura (decae por día);
/// 3. se diversifica: como mucho [maxPerSource] por medio;
/// 4. se limpian imágenes genéricas (el logo de Yahoo Finance que Finnhub
///    pone como "imagen" de todos los artículos sindicados).
abstract final class NewsRelevanceRanker {
  static const maxPerSource = 2;

  /// Medios con redacción propia, primero. Comparación por minúsculas y
  /// por contención ("CNBC" matchea "cnbc.com" o "CNBC Television").
  static const _trustedSources = [
    'reuters',
    'bloomberg',
    'cnbc',
    'wsj',
    'wall street journal',
    'financial times',
    'marketwatch',
    'barron',
    'associated press',
    'ap news',
    'axios',
    'new york times',
    'nytimes',
    'morningstar',
    'fortune',
    'the verge',
    'techcrunch',
    'investor\'s business daily',
    'business wire',
    'businesswire',
    'pr newswire',
    'prnewswire',
    'globenewswire',
  ];

  /// Útiles pero de menor peso: agregadores y análisis de terceros.
  static const _secondarySources = ['benzinga', 'seekingalpha', 'yahoo'];

  /// Una imagen repetida en tantos artículos del mismo lote es un
  /// placeholder del agregador, no la portada de la nota.
  static const _genericImageRepeats = 3;

  /// [feedIsRanked]: el orden de [items] ya es de relevancia (Google
  /// News) y suma como señal; si no (Finnhub, por fecha), se ignora.
  static List<CompanyNewsItem> rank(
    List<CompanyNewsItem> items, {
    required String ticker,
    String? companyName,
    required int limit,
    DateTime? now,
    bool feedIsRanked = false,
  }) {
    final clock = now ?? DateTime.now().toUtc();
    final matchers = _matchers(ticker, companyName);
    final genericImages = _genericImages(items);

    final scored = <({CompanyNewsItem item, double score})>[];
    final seenHeadlines = <String>{};
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final headline = item.headline.toLowerCase();
      final summary = item.summary.toLowerCase();
      final inHeadline = matchers.any((m) => m.hasMatch(headline));
      final inSummary = matchers.any((m) => m.hasMatch(summary));
      if (!inHeadline && !inSummary) continue;
      // El mismo titular sindicado por dos medios cuenta una vez.
      if (!seenHeadlines.add(_normalizeHeadline(headline))) continue;

      final ageDays = clock.difference(item.publishedAt).inHours / 24;
      final score =
          (inHeadline ? 3.0 : 1.0) +
          _sourceWeight(item.source) +
          // Frescura: una nota de hoy suma 2, una de hace una semana ~0.
          (2.0 - ageDays * 0.3).clamp(0.0, 2.0) +
          (feedIsRanked ? (2.0 - index * 0.1).clamp(0.0, 2.0) : 0.0);
      scored.add((item: _withCleanImage(item, genericImages), score: score));
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0
          ? byScore
          : b.item.publishedAt.compareTo(a.item.publishedAt);
    });

    final cluster = _clusterByEvent([
      for (final s in scored.take(_clusterPool)) s.item.headline,
    ], companyWords: _companyWords(ticker, companyName));
    final perSource = <String, int>{};
    final usedClusters = <int>{};
    final picked = <CompanyNewsItem>[];
    for (var i = 0; i < scored.length; i++) {
      final item = scored[i].item;
      final key = item.source.toLowerCase();
      final count = perSource[key] ?? 0;
      if (count >= maxPerSource) continue;
      // Un mismo hecho cubierto por ocho medios (la plataforma de seguridad
      // de Nvidia en Reuters, CNBC, AP, CNN…) se muestra una vez: la mejor
      // puntuada, que es la primera que aparece en este orden.
      if (i < cluster.length && !usedClusters.add(cluster[i])) continue;
      perSource[key] = count + 1;
      picked.add(item);
      if (picked.length >= limit) break;
    }
    return picked;
  }

  /// Solo se agrupan los mejores N: más abajo no se va a elegir nada.
  static const _clusterPool = 40;

  /// Dos titulares son el mismo hecho si comparten al menos
  /// [_minSharedWords] palabras significativas y eso es al menos
  /// [_sameEvent] del más corto. Calibrado con titulares reales de Google
  /// News (NVDA/AAPL/KO, sep-2026): "Nvidia releases software platform to
  /// stop AI agents…" y "Nvidia unveils security platform to stop AI
  /// agents…" se agrupan; "Nvidia stock falls" y "Nvidia stock rises", no.
  static const _minSharedWords = 2;

  /// Agrupamiento transitivo (union-find): si A≈B y B≈C, los tres son un
  /// hecho aunque A y C no compartan palabras — p. ej. el comunicado
  /// "\$150 Billion Share Repurchase", el "Record \$150 Billion Buyback" del
  /// WSJ y el "record buyback" de CNBC. Devuelve el id de grupo por índice.
  static List<int> _clusterByEvent(
    List<String> headlines, {
    required Set<String> companyWords,
  }) {
    final tokens = [
      for (final h in headlines) _tokens(h).difference(companyWords),
    ];
    final parent = List<int>.generate(headlines.length, (i) => i);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    for (var a = 0; a < tokens.length; a++) {
      for (var b = a + 1; b < tokens.length; b++) {
        final shared = tokens[a].intersection(tokens[b]).length;
        if (shared >= _minSharedWords &&
            _similarity(tokens[a], tokens[b]) >= _sameEvent) {
          parent[find(b)] = find(a);
        }
      }
    }
    return [for (var i = 0; i < headlines.length; i++) find(i)];
  }

  /// El nombre de la compañía está en casi todos los titulares: contarlo
  /// como coincidencia agruparía hechos distintos.
  static Set<String> _companyWords(String ticker, String? companyName) => {
    ticker.toLowerCase(),
    ..._tokens(_coreName(companyName) ?? ''),
    ...(_coreName(companyName) ?? '').split(RegExp(r'[^a-z0-9]+')),
  };

  /// Sinónimos frecuentes en titulares financieros, llevados a una forma.
  static const _synonyms = {
    'repurchase': 'buyback',
    'unveil': 'launch',
    'unveiled': 'launch',
    'release': 'launch',
    'released': 'launch',
    'introduce': 'launch',
    'debut': 'launch',
    'launche': 'launch',
    'launched': 'launch',
    'hire': 'appoint',
    'hired': 'appoint',
    'name': 'appoint',
    'named': 'appoint',
    'verdict': 'jury',
    'lawsuit': 'suit',
    'earning': 'result',
    'quarterly': 'quarter',
  };

  static const _sameEvent = 0.3;

  static const _stopwords = {
    'the',
    'and',
    'for',
    'with',
    'from',
    'that',
    'this',
    'into',
    'after',
    'over',
    'amid',
    'says',
    'said',
    'will',
    'stock',
    'stocks',
    'shares',
    'share',
    'its',
    'are',
    'has',
    'have',
    'what',
    'why',
    'how',
    'here',
    'new',
    'could',
    'just',
    'now',
    'more',
    'than',
    'about',
    'your',
    'you',
    'billion',
    'million',
  };

  static Set<String> _tokens(String headline) => {
    for (final w in headline.toLowerCase().split(RegExp(r'[^a-z0-9\$]+')))
      if (w.length >= 3 && !_stopwords.contains(w))
        _synonyms[_stem(w)] ?? _stem(w),
  };

  /// Stem mínimo: "buybacks"/"buyback", "announces"/"announce".
  static String _stem(String w) =>
      w.length > 4 && w.endsWith('s') ? w.substring(0, w.length - 1) : w;

  /// Overlap coefficient (|A∩B| / min|A|,|B|): tolera que un titular sea
  /// mucho más largo que otro sobre el mismo hecho, a diferencia de Jaccard.
  static double _similarity(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final shared = a.intersection(b).length;
    return shared / (a.length < b.length ? a.length : b.length);
  }

  static double _sourceWeight(String source) {
    final s = source.toLowerCase();
    if (_trustedSources.any(s.contains)) return 2.0;
    if (_secondarySources.any(s.contains)) return 0.5;
    return 1.0;
  }

  /// "NVIDIA Corp" → matchea "nvidia"; "Coca-Cola Co" → "coca-cola";
  /// el ticker siempre como palabra suelta (para no matchear "KO" dentro
  /// de "Kodak").
  static List<RegExp> _matchers(String ticker, String? companyName) {
    final patterns = <String>{
      r'\b' + RegExp.escape(ticker.toLowerCase()) + r'\b',
    };
    final core = _coreName(companyName);
    if (core != null) {
      patterns.add(r'\b' + RegExp.escape(core));
      final first = core.split(' ').first;
      if (first.length >= 4 && first != core) {
        patterns.add(r'\b' + RegExp.escape(first) + r'\b');
      }
    }
    return [for (final p in patterns) RegExp(p)];
  }

  static const _suffixes = {
    'inc',
    'inc.',
    'corp',
    'corp.',
    'corporation',
    'co',
    'co.',
    'company',
    'ltd',
    'ltd.',
    'plc',
    'holdings',
    'group',
    'sa',
    'nv',
    'ag',
    'the',
    'class',
    'a',
    'b',
    '&',
  };

  static String? _coreName(String? name) {
    if (name == null) return null;
    final words =
        name
            .toLowerCase()
            .replaceAll(',', ' ')
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty && !_suffixes.contains(w))
            .toList();
    if (words.isEmpty) return null;
    final core = words.join(' ');
    return core.length >= 3 ? core : null;
  }

  static Set<String> _genericImages(List<CompanyNewsItem> items) {
    final counts = <String, int>{};
    for (final item in items) {
      final url = item.imageUrl;
      if (url != null) counts[url] = (counts[url] ?? 0) + 1;
    }
    return {
      for (final e in counts.entries)
        if (e.value >= _genericImageRepeats) e.key,
    };
  }

  static CompanyNewsItem _withCleanImage(
    CompanyNewsItem item,
    Set<String> generic,
  ) {
    final url = item.imageUrl;
    if (url == null || !generic.contains(url)) return item;
    return CompanyNewsItem(
      ticker: item.ticker,
      headline: item.headline,
      summary: item.summary,
      url: item.url,
      source: item.source,
      publishedAt: item.publishedAt,
      sourceDomain: item.sourceDomain,
    );
  }

  static String _normalizeHeadline(String headline) =>
      headline.replaceAll(RegExp(r'[^a-z0-9]'), '');
}
