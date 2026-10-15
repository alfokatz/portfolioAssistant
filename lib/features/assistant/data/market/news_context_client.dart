import 'package:portfolio_assistant/features/assistant/data/market/ttl_cache.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/porty_edge_client.dart';

/// "Qué está pasando y por qué" (edge function `news-context`): búsqueda
/// web de OpenAI en el servidor, restringida a medios permitidos, con citas.
/// La caché fuerte está en el servidor (compartida, 45 min); acá solo se
/// evita repetir la misma consulta dentro de la conversación.
class NewsContextClient {
  NewsContextClient({PortyEdgeClient? client, Duration? cacheTtl})
    : _client = client ?? PortyEdgeClient(),
      _cache = TtlCache(cacheTtl ?? const Duration(minutes: 30));

  final PortyEdgeClient _client;
  final TtlCache<Map<String, Object?>> _cache;

  /// `{status: ok|empty|failed|limit|locked, summary: [..], sources:
  /// [{title, url, source}]}`. Nunca lanza.
  Future<Map<String, Object?>> fetch(
    List<String> tickers, {
    Map<String, String> names = const {},
    String? question,
    String lang = 'es',
  }) async {
    final key = '${(List.of(tickers)..sort()).join(',')}|${question ?? ''}|$lang';
    final cached = _cache.get(key);
    if (cached != null) return cached;

    final response = await _client.post('news-context', {
      'tickers': tickers,
      if (names.isNotEmpty) 'names': names,
      if (question != null && question.isNotEmpty) 'question': question,
      'lang': lang,
    });
    if (response.planRequired) {
      return const {'status': 'locked', 'required_plan': 'gold'};
    }
    if (!response.ok) {
      final type = response.errorType;
      if (type == 'daily_limit' || type == 'turn_limit') {
        return {'status': 'limit', 'reason': type};
      }
      return const {'status': 'failed'};
    }
    final body = response.body!;
    final summary = [
      for (final line in (body['summary'] as List? ?? const []))
        if ('$line'.trim().isNotEmpty) '$line'.trim(),
    ];
    final sources = [
      for (final c in (body['citations'] as List? ?? const []).whereType<Map>())
        if ('${c['url'] ?? ''}'.startsWith('http'))
          {
            'title': '${c['title'] ?? ''}',
            'url': '${c['url']}',
            'source': '${c['source'] ?? ''}',
          },
    ];
    final ok = body['status'] == 'ok' && summary.isNotEmpty;
    final result = <String, Object?>{
      'status': ok ? 'ok' : 'empty',
      if (ok) 'summary': summary,
      // Sin resumen no hay fuentes: se mostraban bajo un "no hay noticias".
      if (ok && sources.isNotEmpty) 'sources': sources,
      if (body['as_of'] != null) 'searched_at': body['as_of'],
    };
    // Lo vacío no: el servidor ya lo guarda solo 10 min y vuelve a buscar.
    if (result['status'] == 'ok') _cache.put(key, result);
    return result;
  }
}
