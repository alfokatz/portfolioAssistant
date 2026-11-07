import 'dart:convert';

/// Lo que escribe Porty para el informe: solo prosa y referencias por id a
/// los datos. Los números, links, fuentes y preguntas sugeridas los pone la
/// app.
class WeeklyReportDraft {
  const WeeklyReportDraft({
    required this.reading,
    required this.movers,
    required this.headlines,
    required this.investors,
    this.learn,
  });

  static const empty = WeeklyReportDraft(
    reading: null,
    movers: [],
    headlines: [],
    investors: [],
  );

  /// La frase de lectura de la semana: lo que el número solo no dice.
  final String? reading;
  final List<DraftMover> movers;

  /// Titulares reescritos en español (sección "Noticias de la semana").
  final List<DraftHeadline> headlines;
  final List<DraftInvestor> investors;
  final DraftLearn? learn;

  bool get isEmpty =>
      reading == null &&
      movers.isEmpty &&
      headlines.isEmpty &&
      investors.isEmpty &&
      learn == null;

  /// Parsea la respuesta del modelo. Tolera texto alrededor del JSON (un
  /// ```json …```) y campos faltantes; `null` si no hay un objeto JSON.
  static WeeklyReportDraft? tryParse(String raw) {
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

  static WeeklyReportDraft fromJson(Map<String, Object?> j) {
    List<Map<String, Object?>> list(String key) => [
      for (final e in (j[key] as List?) ?? const [])
        if (e is Map) e.cast<String, Object?>(),
    ];
    final learn = j['learn'];
    return WeeklyReportDraft(
      reading: _text(j['reading']),
      movers: [
        for (final m in list('movers'))
          if (_text(m['ticker']) != null && _text(m['why']) != null)
            DraftMover(
              ticker: _text(m['ticker'])!.toUpperCase(),
              why: _text(m['why'])!,
              newsId: _text(m['news_id']),
            ),
      ],
      headlines: [
        for (final h in list('headlines'))
          if (_text(h['news_id']) != null && _text(h['title_es']) != null)
            DraftHeadline(
              newsId: _text(h['news_id'])!,
              title: _text(h['title_es'])!,
            ),
      ],
      investors: [
        for (final i in list('investors'))
          if (_text(i['item_id']) != null && _text(i['take']) != null)
            DraftInvestor(
              itemId: _text(i['item_id'])!,
              take: _text(i['take'])!,
            ),
      ],
      learn:
          learn is Map &&
                  _text(learn['concept']) != null &&
                  _text(learn['text']) != null
              ? DraftLearn(
                topic: _text(learn['topic']),
                concept: _text(learn['concept'])!,
                text: _text(learn['text'])!,
              )
              : null,
    );
  }

  Map<String, Object?> toJson() => {
    'reading': reading,
    'movers': [
      for (final m in movers)
        {'ticker': m.ticker, 'why': m.why, 'news_id': m.newsId},
    ],
    'headlines': [
      for (final h in headlines) {'news_id': h.newsId, 'title_es': h.title},
    ],
    'investors': [
      for (final i in investors) {'item_id': i.itemId, 'take': i.take},
    ],
    'learn':
        learn == null
            ? null
            : {
              'topic': learn!.topic,
              'concept': learn!.concept,
              'text': learn!.text,
            },
  };

  static String? _text(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}

class DraftMover {
  const DraftMover({required this.ticker, required this.why, this.newsId});
  final String ticker;
  final String why;
  final String? newsId;
}

class DraftHeadline {
  const DraftHeadline({required this.newsId, required this.title});
  final String newsId;
  final String title;
}

class DraftInvestor {
  const DraftInvestor({required this.itemId, required this.take});
  final String itemId;
  final String take;
}

class DraftLearn {
  const DraftLearn({this.topic, required this.concept, required this.text});

  /// El `learn_topic` que eligió la app para esta semana.
  final String? topic;
  final String concept;
  final String text;
}
