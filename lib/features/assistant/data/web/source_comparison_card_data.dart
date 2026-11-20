import 'package:portfolio_assistant/features/assistant/tools/web_tools.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';

/// Una fuente con link de la comparación.
class ComparisonSource {
  const ComparisonSource({
    required this.outlet,
    required this.title,
    required this.url,
  });

  final String outlet;
  final String title;
  final String url;
}

/// Una fila de la card: lo que coinciden, en qué difieren o lo que dijo un
/// solo medio.
class ComparisonPoint {
  const ComparisonPoint({
    required this.kind,
    required this.text,
    required this.sources,
  });

  /// `agree` | `differ` | `only`.
  final String kind;
  final String text;
  final List<ComparisonSource> sources;
}

/// Lo que dibuja `QaSourceComparison`: sale del resultado de
/// `compare_sources` del turno (nunca del modelo), así cada fila tiene su
/// medio y su link y ningún medio puede ser inventado.
class SourceComparisonCardData {
  const SourceComparisonCardData({
    required this.subject,
    required this.points,
    required this.outlets,
    this.ticker,
  });

  final String subject;

  /// El ticker comparado (`null` si fue un tema): para los seguimientos.
  final String? ticker;
  final List<ComparisonPoint> points;
  final List<String> outlets;

  /// Los puntos de [kind], en el orden del servidor.
  List<ComparisonPoint> of(String kind) => [
    for (final p in points)
      if (p.kind == kind) p,
  ];

  /// La comparación `ok` más reciente de la evidencia, o `null`.
  static SourceComparisonCardData? from(TurnEvidence evidence) {
    for (final call in evidence.calls.reversed) {
      if (call.name != CompareSourcesTool.toolName || call.status != 'ok') {
        continue;
      }
      final r = call.result;
      final sources = r['sources'];
      final points = <ComparisonPoint>[];
      for (final p in (r['points'] as List? ?? const []).whereType<Map>()) {
        final linked = <ComparisonSource>[];
        for (final id in (p['source_ids'] as List? ?? const [])) {
          final s = sources is Map ? sources['$id'] : null;
          if (s is! Map || !'${s['url'] ?? ''}'.startsWith('https://')) {
            continue;
          }
          linked.add(
            ComparisonSource(
              outlet: '${s['source'] ?? ''}',
              title: '${s['title'] ?? ''}',
              url: '${s['url']}',
            ),
          );
        }
        final text = '${p['text'] ?? ''}'.trim();
        if (linked.isEmpty || text.isEmpty) continue;
        points.add(
          ComparisonPoint(kind: '${p['kind']}', text: text, sources: linked),
        );
      }
      if (points.isEmpty) return null;
      return SourceComparisonCardData(
        subject: '${r['subject'] ?? ''}',
        ticker: call.args['ticker'] is String
            ? (call.args['ticker'] as String).toUpperCase()
            : null,
        points: points,
        outlets: [for (final o in (r['outlets'] as List? ?? const [])) '$o'],
      );
    }
    return null;
  }
}
