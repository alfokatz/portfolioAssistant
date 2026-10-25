import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

/// Una fuente con link que respalda una respuesta.
class MessageSource {
  const MessageSource({required this.url, this.title = '', this.source = ''});

  final String url;
  final String title;

  /// El medio ("Reuters") o "SEC EDGAR".
  final String source;

  String get host =>
      (Uri.tryParse(url)?.host ?? '').replaceFirst(RegExp(r'^www\.'), '');
}

/// Las fuentes con link que usó un turno, para mostrarlas debajo de la
/// respuesta: las citas de la búsqueda web (OpenAI exige que se vean y se
/// puedan tocar) y las presentaciones a la SEC de donde salieron resultados
/// y fundamentals. Las pone la app, no el modelo.
abstract final class AnswerSources {
  static const max = 8;

  static List<MessageSource> of(List<ToolCallRecord> calls) {
    final out = <MessageSource>[];
    final seen = <String>{};
    void add(Object? url, String title, String source) {
      final u = '${url ?? ''}'.trim();
      if (!u.startsWith('https://') || !seen.add(u)) return;
      out.add(MessageSource(url: u, title: title.trim(), source: source.trim()));
    }

    for (final call in calls) {
      final result = call.result;
      switch (call.name) {
        case 'get_news':
          // Los titulares ya se ven en la card de noticias: una cita con el
          // mismo link no se repite en "Fuentes".
          final news = result['news'];
          final inCard = {
            for (final n in (news is List ? news : const []).whereType<Map>())
              '${n['url'] ?? ''}'.trim(),
          };
          final context = result['context'];
          final sources = context is Map ? context['sources'] : null;
          for (final s in (sources is List ? sources : const []).whereType<Map>()) {
            if (inCard.contains('${s['url'] ?? ''}'.trim())) continue;
            add(s['url'], '${s['title'] ?? ''}', '${s['source'] ?? ''}');
          }
        case 'search_web':
          final sources = result['sources'];
          for (final s in (sources is List ? sources : const []).whereType<Map>()) {
            final url = '${s['url'] ?? ''}';
            add(url, '${s['title'] ?? ''}', MessageSource(url: url).host);
          }
        case 'get_earnings' || 'get_fundamentals':
          final byTicker =
              result[call.name == 'get_earnings' ? 'earnings' : 'fundamentals'];
          if (byTicker is! Map) break;
          for (final MapEntry(key: ticker, value: entry) in byTicker.entries) {
            if (entry is! Map || entry['source'] != 'SEC EDGAR') continue;
            final release = entry['press_release'];
            if (release is Map && release['url'] != null) {
              final form = '${release['form'] ?? ''}';
              add(
                release['url'],
                'Comunicado de resultados de $ticker'
                '${form.isEmpty ? '' : ' ($form)'}',
                'SEC EDGAR',
              );
            } else {
              add(entry['source_url'], 'Presentaciones de $ticker', 'SEC EDGAR');
            }
          }
      }
    }
    return out.take(max).toList();
  }
}
