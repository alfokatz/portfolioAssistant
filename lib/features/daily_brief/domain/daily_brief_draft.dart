import 'dart:convert';

import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_input.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_writer.dart';

/// Lo que escribe Porty para el brief: solo prosa y referencias por id a los
/// datos (§3.4). La app pone los números, el medio, el link y el ticker.
class DailyBriefDraft {
  const DailyBriefDraft({
    this.why = const [],
    this.held = const [],
    this.watch = const [],
    this.market = const [],
  });

  static const empty = DailyBriefDraft();

  /// "Por qué" de las posiciones que más movieron (cuelga de un titular).
  final List<DraftBriefLine> why;

  /// Noticias de la cartera y de la watchlist (Gold).
  final List<DraftBriefLine> held;
  final List<DraftBriefLine> watch;

  /// La `connection` de cada hecho de mercado (`null` = sin conexión).
  final List<DraftConnection> market;

  bool get isEmpty =>
      why.isEmpty &&
      held.isEmpty &&
      watch.isEmpty &&
      market.every((m) => m.connection == null);

  /// Cantidad de ítems con texto (para contar los que el validador sacó).
  int get itemCount =>
      why.length +
      held.length +
      watch.length +
      market.where((m) => m.connection != null).length;

  /// Parsea la respuesta del modelo. Tolera texto alrededor del JSON (un
  /// ```json …```) y campos faltantes; `null` si no hay un objeto JSON.
  static DailyBriefDraft? tryParse(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw.substring(start, end + 1));
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    return fromJson(decoded.cast<String, Object?>());
  }

  static DailyBriefDraft fromJson(Map<String, Object?> j) {
    List<Map<String, Object?>> list(String key) => [
      for (final e in (j[key] as List?) ?? const [])
        if (e is Map) e.cast<String, Object?>(),
    ];
    List<DraftBriefLine> lines(String key) => [
      for (final l in list(key))
        if (_text(l['news_id']) != null && _text(l['text']) != null)
          DraftBriefLine(newsId: _text(l['news_id'])!, text: _text(l['text'])!),
    ];
    return DailyBriefDraft(
      why: lines('why'),
      held: lines('held_news'),
      watch: lines('watch_news'),
      market: [
        for (final m in list('market'))
          if (_text(m['topic_id']) != null)
            DraftConnection(
              topicId: _text(m['topic_id'])!,
              connection: _text(m['connection']),
            ),
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'why': [for (final l in why) l.toJson()],
    'held_news': [for (final l in held) l.toJson()],
    'watch_news': [for (final l in watch) l.toJson()],
    'market': [
      for (final m in market)
        {'topic_id': m.topicId, 'connection': m.connection},
    ],
  };

  /// La prosa que consume `DailyBriefController`: el ticker de cada línea
  /// sale del titular (el modelo no lo escribe, así no puede desalinearse).
  /// Una línea sin titular conocido se descarta.
  DailyBriefProse toProse(DailyBriefInput input) {
    final tickerById = {
      for (final h in [...input.held, ...input.watch]) h.id: h.ticker,
    };
    List<BriefLine> map(List<DraftBriefLine> lines) => [
      for (final l in lines)
        if (tickerById[l.newsId] != null)
          BriefLine(
            ticker: tickerById[l.newsId]!,
            text: l.text,
            newsId: l.newsId,
          ),
    ];
    return DailyBriefProse(
      why: map(why),
      held: map(held),
      watch: map(watch),
      connections: {
        for (final m in market)
          if (m.connection != null) m.topicId: m.connection,
      },
    );
  }

  static String? _text(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}

/// Una línea que cuelga de un titular (`news_id`).
class DraftBriefLine {
  const DraftBriefLine({required this.newsId, required this.text});
  final String newsId;
  final String text;

  Map<String, Object?> toJson() => {'news_id': newsId, 'text': text};
}

/// La conexión de un hecho de mercado con lo que el usuario tiene.
class DraftConnection {
  const DraftConnection({required this.topicId, this.connection});
  final String topicId;
  final String? connection;
}
