import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_bundle.dart';

/// Una noticia del feed (`mine` o `topic_news`): título, medio y link. Nunca
/// se copia texto del artículo. [ticker] falta en las de un tema.
class NewsArticle {
  const NewsArticle({
    required this.id,
    required this.title,
    required this.source,
    required this.domain,
    required this.url,
    this.ticker,
    this.watch = false,
    this.publishedAt,
    this.preferred = false,
    this.imageUrl,
  });

  final String id;
  final String? ticker;

  /// `kind: watch` (solo Gold). Si no, de la cartera o de un tema.
  final bool watch;
  final String title;
  final String source;
  final String domain;
  final String url;
  final DateTime? publishedAt;
  final bool preferred;

  /// Foto de la nota (`image_url`, https), si el servidor la trae.
  final String? imageUrl;

  static NewsArticle? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    final source = raw['source'];
    final url = raw['url'];
    if (id is! String || title is! String || title.trim().isEmpty) return null;
    if (source is! String || url is! String) return null;
    return NewsArticle(
      id: id,
      title: title,
      source: source,
      domain: raw['domain'] is String ? raw['domain'] as String : '',
      url: url,
      ticker: raw['ticker'] is String ? raw['ticker'] as String : null,
      watch: raw['kind'] == 'watch',
      publishedAt: DateTime.tryParse('${raw['published_at']}'),
      preferred: raw['preferred'] == true,
      imageUrl: parseImageUrl(raw['image_url']),
    );
  }
}

/// Una viñeta del resumen de un tema: una oración con sus fuentes.
class NewsDigestLine {
  const NewsDigestLine({required this.text, required this.sourceIds});

  final String text;
  final List<String> sourceIds;

  static NewsDigestLine? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    if (text is! String || text.trim().isEmpty) return null;
    final ids = raw['source_ids'];
    return NewsDigestLine(
      text: text,
      sourceIds: ids is List ? ids.whereType<String>().toList() : const [],
    );
  }
}

/// `ok` | `empty` | `failed`: un tema que falló no tumba el resto.
enum NewsDigestStatus { ok, empty, failed }

class NewsTopicDigest {
  const NewsTopicDigest({
    required this.topicId,
    required this.label,
    required this.status,
    this.lines = const [],
    this.asOf,
  });

  final String topicId;
  final String label;
  final NewsDigestStatus status;
  final List<NewsDigestLine> lines;
  final DateTime? asOf;

  static NewsTopicDigest? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['topic_id'];
    final label = raw['label'];
    if (id is! String || label is! String) return null;
    final lines = raw['summary'];
    return NewsTopicDigest(
      topicId: id,
      label: label,
      status: switch (raw['status']) {
        'ok' => NewsDigestStatus.ok,
        'failed' => NewsDigestStatus.failed,
        _ => NewsDigestStatus.empty,
      },
      lines:
          lines is List
              ? lines
                  .map(NewsDigestLine.tryParse)
                  .whereType<NewsDigestLine>()
                  .toList()
              : const [],
      asOf: DateTime.tryParse('${raw['as_of']}'),
    );
  }
}

/// Una referencia de "Mercado hoy" (índice, materia prima, tasa…). El
/// orden es el del catálogo: nunca se reordena por el tamaño del movimiento.
class NewsInstrument {
  const NewsInstrument({
    required this.symbol,
    required this.label,
    required this.kind,
    this.pct,
    this.asOf,
  });

  final String symbol;
  final String label;
  final String kind;

  /// Variación del último cierre; `null` si no hay dato.
  final double? pct;
  final DateTime? asOf;

  static NewsInstrument? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final symbol = raw['symbol'];
    final label = raw['label'];
    if (symbol is! String || label is! String) return null;
    final pct = raw['pct'];
    return NewsInstrument(
      symbol: symbol,
      label: label,
      kind: raw['kind'] is String ? raw['kind'] as String : 'index',
      pct: pct is num && pct.isFinite ? pct.toDouble() : null,
      asOf: DateTime.tryParse('${raw['as_of']}'),
    );
  }
}

/// Un video de un canal oficial de un medio (YouTube).
class NewsVideo {
  const NewsVideo({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.url,
    this.topicId,
    this.publishedAt,
    this.thumbnail,
    this.serverEmbeddable,
  });

  final String videoId;
  final String title;
  final String channel;
  final String url;
  final String? topicId;
  final DateTime? publishedAt;
  final String? thumbnail;

  /// Lo que dice el servidor (`embeddable`); `null` si el bundle es viejo y
  /// no trae el campo.
  final bool? serverEmbeddable;

  static final _id = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Se muestra el reproductor solo si el id tiene forma de YouTube (11
  /// caracteres) y el servidor no dijo `false`. Sin el campo, solo el id.
  bool get embeddable => serverEmbeddable != false && _id.hasMatch(videoId);

  static NewsVideo? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['video_id'];
    final title = raw['title'];
    final channel = raw['channel'];
    final url = raw['url'];
    if (id is! String || title is! String || channel is! String) return null;
    if (url is! String) return null;
    final thumb = raw['thumbnail'];
    return NewsVideo(
      videoId: id,
      title: title,
      channel: channel,
      url: url,
      topicId: raw['topic_id'] is String ? raw['topic_id'] as String : null,
      publishedAt: DateTime.tryParse('${raw['published_at']}'),
      thumbnail: thumb is String && thumb.startsWith('https://') ? thumb : null,
      serverEmbeddable:
          raw['embeddable'] is bool ? raw['embeddable'] as bool : null,
    );
  }
}

/// Por qué una lista de notas está vacía (`mine_status`, `topic_news_status`):
/// `empty` = no hubo noticias; `unavailable` = no se pudo consultar ahora.
/// `null` si el servidor no lo dice (Free, bundle viejo).
enum NewsListStatus {
  ok,
  empty,
  unavailable;

  static NewsListStatus? parse(Object? raw) => switch (raw) {
    'ok' => NewsListStatus.ok,
    'empty' => NewsListStatus.empty,
    'unavailable' => NewsListStatus.unavailable,
    _ => null,
  };
}

/// La respuesta de `daily-brief` para `feed`, `topic` y `market` (§3.5).
/// Tolerante: un bloque que falta o viene roto llega vacío.
class NewsBundle {
  const NewsBundle({
    this.tier = 'free',
    this.mine = const [],
    this.mineStatus,
    this.topicNewsStatus,
    this.lockedCount,
    this.topics = const [],
    this.topicNews = const [],
    this.instruments = const [],
    this.pulse = const [],
    this.videos = const [],
    this.sources = const {},
    this.asOf,
  });

  static const empty = NewsBundle();

  final String tier;

  /// Titulares de la cartera (y, en Gold, de la watchlist).
  final List<NewsArticle> mine;

  /// Por qué [mine] está vacía (solo Premium/Gold).
  final NewsListStatus? mineStatus;

  /// Lo mismo para [topicNews] (scope `topic`).
  final NewsListStatus? topicNewsStatus;

  /// Free: cuántos tickers de su cartera tienen noticias en 48 h. Sin
  /// tickers. `null` si el plan sí ve [mine].
  final int? lockedCount;
  final List<NewsTopicDigest> topics;

  /// Titulares de un tema (scope `topic`).
  final List<NewsArticle> topicNews;
  final List<NewsInstrument> instruments;
  final List<BriefMarketFact> pulse;
  final List<NewsVideo> videos;
  final Map<String, BriefSource> sources;
  final DateTime? asOf;

  static NewsBundle parse(Map<String, Object?> body) {
    final plan = body['plan'];
    final market = body['market'];
    final locked = body['locked'];
    final sources = body['sources'];
    List<T> list<T>(Object? raw, T? Function(Object?) parse) =>
        raw is List ? raw.map(parse).whereType<T>().toList() : <T>[];
    final count = locked is Map ? locked['mine_tickers_48h'] : null;
    return NewsBundle(
      tier:
          plan is Map && plan['tier'] is String
              ? plan['tier'] as String
              : 'free',
      mine: list(body['mine'], NewsArticle.tryParse),
      mineStatus: NewsListStatus.parse(body['mine_status']),
      topicNewsStatus: NewsListStatus.parse(body['topic_news_status']),
      lockedCount: count is num ? count.toInt() : null,
      topics: list(body['topics'], NewsTopicDigest.tryParse),
      topicNews: list(body['topic_news'], NewsArticle.tryParse),
      instruments: list(
        market is Map ? market['instruments'] : null,
        NewsInstrument.tryParse,
      ),
      pulse: list(
        market is Map ? market['pulse'] : null,
        BriefMarketFact.tryParse,
      ),
      videos: list(body['videos'], NewsVideo.tryParse),
      sources: {
        if (sources is Map)
          for (final e in sources.entries)
            if (e.key is String)
              if (BriefSource.tryParse(e.value) case final s?)
                e.key as String: s,
      },
      asOf: DateTime.tryParse('${body['as_of']}'),
    );
  }

  /// La primera fuente citada por [ids] que exista.
  BriefSource? sourceOf(List<String> ids) {
    for (final id in ids) {
      final s = sources[id];
      if (s != null) return s;
    }
    return null;
  }

  bool get isLocked => lockedCount != null;
}
