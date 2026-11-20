import 'package:portfolio_assistant/features/assistant/data/market/ttl_cache.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/porty_edge_client.dart';

/// "Qué dice cada medio" (edge function `news-compare`, spec 2026-11-20 §3.6):
/// cómo cubren distintos medios de la allowlist la misma noticia, con
/// atribución validada en el servidor. La caché fuerte (6 h, compartida) está
/// en el servidor; acá solo se evita repetir la misma comparación dentro de
/// la conversación.
class SourceCompareFetcher {
  SourceCompareFetcher({PortyEdgeClient? client, Duration? cacheTtl})
    : _client = client ?? PortyEdgeClient(),
      _cache = TtlCache(cacheTtl ?? const Duration(minutes: 30));

  final PortyEdgeClient _client;
  final TtlCache<Map<String, Object?>> _cache;

  /// Los tipos de punto que el servidor puede mandar.
  static const kinds = {'agree', 'differ', 'only'};

  /// `{status: ok|empty|insufficient_sources|limit|locked|failed, …}`:
  /// - `ok` trae `subject`, `points` [{kind, text, source_ids}], `outlets` y
  ///   `sources` {id: {title, source, url}} (cada punto con al menos una
  ///   fuente con link);
  /// - `limit` lleva `reason` (`turn_limit`, `daily_limit`, `monthly_limit`,
  ///   `rate_limited`);
  /// - `failed` lleva `reason: disabled` si el interruptor está apagado.
  ///
  /// Exactamente uno de [ticker] o [topicId]. Nunca lanza.
  Future<Map<String, Object?>> fetch({
    String? ticker,
    String? topicId,
    String? storyUrl,
    String lang = 'es',
    String? turnId,
  }) async {
    if ((ticker == null) == (topicId == null)) {
      return const {'status': 'failed', 'reason': 'invalid_arguments'};
    }
    final story = storyUrl != null && storyUrl.startsWith('https://')
        ? storyUrl
        : null;
    final key = '${ticker ?? 'topic:$topicId'}|${story ?? ''}|$lang';
    final cached = _cache.get(key);
    if (cached != null) return cached;

    final EdgeResponse response;
    try {
      response = await _client.post('news-compare', {
        if (ticker != null) 'ticker': ticker,
        if (topicId != null) 'topic_id': topicId,
        if (story != null) 'story_url': story,
        'lang': lang,
      }, turnId: turnId);
    } catch (_) {
      return const {'status': 'failed'};
    }
    if (!response.ok) return _error(response);

    final result = parse(response.body!);
    // Lo que no es una comparación lista no se guarda: el servidor ya decide
    // cuánto cachear lo vacío o insuficiente.
    if (result['status'] == 'ok') _cache.put(key, result);
    return result;
  }

  static Map<String, Object?> _error(EdgeResponse response) {
    if (response.planRequired) {
      final error = response.body?['error'];
      final plan = error is Map ? error['required_plan'] : null;
      return {
        'status': 'locked',
        'required_plan': plan == 'premium' ? 'premium' : 'gold',
      };
    }
    final type = response.errorType;
    if (response.statusCode == 403 && type == 'disabled') {
      return const {'status': 'failed', 'reason': 'disabled'};
    }
    if (const {
      'turn_limit',
      'daily_limit',
      'monthly_limit',
      'rate_limited',
    }.contains(type)) {
      return {'status': 'limit', 'reason': type};
    }
    return const {'status': 'failed'};
  }

  /// El cuerpo del servidor, validado: solo puntos con tipo conocido, texto y
  /// al menos una fuente https. Sin puntos válidos no hay comparación.
  static Map<String, Object?> parse(Map<String, Object?> body) {
    final status = body['status'];
    final asOf = body['as_of'];
    final subject = '${body['subject'] ?? ''}'.trim();
    final outlets = [
      for (final o in (body['outlets'] as List? ?? const []))
        if ('$o'.trim().isNotEmpty) '$o'.trim(),
    ];
    if (status == 'insufficient_sources') {
      return {
        'status': 'insufficient_sources',
        if (subject.isNotEmpty) 'subject': subject,
        'outlets': outlets,
        if (asOf != null) 'as_of': asOf,
      };
    }
    if (status != 'ok') {
      return {'status': 'empty', if (asOf != null) 'as_of': asOf};
    }

    final rawSources = body['sources'];
    final sources = <String, Map<String, Object?>>{
      if (rawSources is Map)
        for (final MapEntry(key: id, value: s) in rawSources.entries)
          if (s is Map && '${s['url'] ?? ''}'.startsWith('https://'))
            '$id': {
              'title': '${s['title'] ?? ''}'.trim(),
              'source': '${s['source'] ?? ''}'.trim(),
              'url': '${s['url']}',
            },
    };
    final points = <Map<String, Object?>>[];
    for (final p in (body['points'] as List? ?? const []).whereType<Map>()) {
      final kind = p['kind'];
      final text = '${p['text'] ?? ''}'.trim();
      final ids = [
        for (final id in (p['source_ids'] as List? ?? const []))
          if (sources.containsKey('$id')) '$id',
      ];
      if (!kinds.contains(kind) || text.isEmpty || ids.isEmpty) continue;
      // "Coinciden" exige dos medios distintos (el servidor ya lo valida; acá
      // una red de seguridad): con uno solo es lo que dijo ese medio.
      final distinct = {for (final id in ids) '${sources[id]!['source']}'};
      points.add({
        'kind': kind == 'agree' && distinct.length < 2 ? 'only' : kind,
        'text': text,
        'source_ids': ids,
      });
    }
    if (points.isEmpty) {
      return {'status': 'empty', if (asOf != null) 'as_of': asOf};
    }
    final used = {for (final p in points) ...(p['source_ids'] as List)};
    return {
      'status': 'ok',
      if (subject.isNotEmpty) 'subject': subject,
      'points': points,
      'outlets': outlets,
      'sources': {
        for (final MapEntry(:key, :value) in sources.entries)
          if (used.contains(key)) key: value,
      },
      if (asOf != null) 'as_of': asOf,
    };
  }
}
