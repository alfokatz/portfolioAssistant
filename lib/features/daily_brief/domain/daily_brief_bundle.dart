/// Un titular que llegó del servidor (`daily-brief`, §3.5): título, medio y
/// link. La app nunca copia texto del artículo.
class BriefHeadline {
  const BriefHeadline({
    required this.id,
    required this.ticker,
    required this.watch,
    required this.title,
    required this.source,
    required this.domain,
    required this.url,
    this.publishedAt,
    this.preferred = false,
  });

  final String id;
  final String ticker;

  /// `kind: watch` (solo Gold). Si no, `held`.
  final bool watch;
  final String title;
  final String source;
  final String domain;
  final String url;
  final DateTime? publishedAt;
  final bool preferred;

  static BriefHeadline? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final ticker = raw['ticker'];
    final title = raw['title'];
    final source = raw['source'];
    final url = raw['url'];
    if (id is! String || ticker is! String || title is! String) return null;
    if (source is! String || url is! String) return null;
    return BriefHeadline(
      id: id,
      ticker: ticker,
      watch: raw['kind'] == 'watch',
      title: title,
      source: source,
      domain: raw['domain'] is String ? raw['domain'] as String : '',
      url: url,
      publishedAt: DateTime.tryParse('${raw['published_at']}'),
      preferred: raw['preferred'] == true,
    );
  }

  Map<String, Object?> toPromptJson() => {
    'id': id,
    'ticker': ticker,
    'title': title,
    'source': source,
  };
}

/// Un hecho de mercado ya redactado y validado por el servidor, con sus
/// fuentes (`market.pulse`).
class BriefMarketFact {
  const BriefMarketFact({
    required this.text,
    required this.sourceIds,
    this.topicId,
    this.assetLink,
    this.assetClass,
  });

  final String text;
  final List<String> sourceIds;
  final String? topicId;

  /// La frase fija del tema ("tenés bonos o ETF de renta fija…"): la
  /// `connection` solo puede parafrasearla.
  final String? assetLink;

  /// La clase de activo del tema (`crypto`, `bond`, `etf`, `equity`).
  final String? assetClass;

  static BriefMarketFact? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    if (text is! String || text.trim().isEmpty) return null;
    final ids = raw['source_ids'];
    return BriefMarketFact(
      text: text,
      sourceIds: ids is List ? ids.whereType<String>().toList() : const [],
      topicId: raw['topic_id'] is String ? raw['topic_id'] as String : null,
      assetLink: raw['asset_link'] is String ? raw['asset_link'] as String : null,
      assetClass:
          raw['asset_class'] is String ? raw['asset_class'] as String : null,
    );
  }
}

/// Un resultado de Gold: presentado (con link al 8-K) o estimado.
class BriefEarning {
  const BriefEarning({
    required this.ticker,
    required this.reported,
    required this.date,
    this.url,
  });

  final String ticker;
  final bool reported;
  final DateTime date;
  final String? url;

  static BriefEarning? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final ticker = raw['ticker'];
    final date = DateTime.tryParse('${raw['date']}');
    if (ticker is! String || date == null) return null;
    return BriefEarning(
      ticker: ticker,
      reported: raw['kind'] == 'reported',
      date: DateTime(date.year, date.month, date.day),
      url: raw['url'] is String ? raw['url'] as String : null,
    );
  }

  Map<String, Object?> toJson() => {
    'ticker': ticker,
    'kind': reported ? 'reported' : 'estimated',
    'date':
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
    'url': url,
  };
}

/// Medio y link de algo que se muestra (`sources`).
class BriefSource {
  const BriefSource({
    required this.title,
    required this.source,
    required this.domain,
    required this.url,
    this.publishedAt,
  });

  final String title;
  final String source;
  final String domain;
  final String url;
  final DateTime? publishedAt;

  static BriefSource? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final title = raw['title'];
    final source = raw['source'];
    final url = raw['url'];
    if (title is! String || source is! String || url is! String) return null;
    return BriefSource(
      title: title,
      source: source,
      domain: raw['domain'] is String ? raw['domain'] as String : '',
      url: url,
      publishedAt: DateTime.tryParse('${raw['published_at']}'),
    );
  }

  Map<String, Object?> toJson() => {
    'title': title,
    'source': source,
    'domain': domain,
    'url': url,
    if (publishedAt != null)
      'published_at': publishedAt!.toUtc().toIso8601String(),
  };
}

/// La respuesta de `daily-brief?scope=brief` (§3.5). Todo tolerante: un
/// bloque que falta o viene roto llega vacío.
class DailyBriefBundle {
  const DailyBriefBundle({
    this.variant = 'numbers',
    this.courtesy = false,
    this.mine = const [],
    this.earnings = const [],
    this.market = const [],
    this.sources = const {},
    this.assetClasses = const {},
  });

  static const empty = DailyBriefBundle();

  /// `full` o `numbers`: lo que el servidor le da a este plan.
  final String variant;
  final bool courtesy;

  /// Titulares de la cartera (`held`) y, solo Gold, de la watchlist.
  final List<BriefHeadline> mine;
  final List<BriefEarning> earnings;
  final List<BriefMarketFact> market;
  final Map<String, BriefSource> sources;

  /// Clases de activo de la cartera del usuario (`asset_classes`).
  final Set<String> assetClasses;

  List<BriefHeadline> get held => [
    for (final h in mine)
      if (!h.watch) h,
  ];

  List<BriefHeadline> get watch => [
    for (final h in mine)
      if (h.watch) h,
  ];

  static DailyBriefBundle parse(Map<String, Object?> body) {
    final plan = body['plan'];
    final market = body['market'];
    final pulse = market is Map ? market['pulse'] : null;
    final sources = body['sources'];
    final mine = body['mine'];
    final earnings = body['earnings'];
    List<T> list<T>(Object? raw, T? Function(Object?) parse) =>
        raw is List ? raw.map(parse).whereType<T>().toList() : <T>[];
    return DailyBriefBundle(
      variant: plan is Map && plan['variant'] == 'full' ? 'full' : 'numbers',
      courtesy: plan is Map && plan['courtesy'] == true,
      mine: list(mine, BriefHeadline.tryParse),
      earnings: list(earnings, BriefEarning.tryParse),
      market: list(pulse, BriefMarketFact.tryParse),
      assetClasses: {
        if (body['asset_classes'] is List)
          ...(body['asset_classes'] as List).whereType<String>(),
      },
      sources: {
        if (sources is Map)
          for (final e in sources.entries)
            if (e.key is String)
              if (BriefSource.tryParse(e.value) case final s?) e.key as String: s,
      },
    );
  }
}
