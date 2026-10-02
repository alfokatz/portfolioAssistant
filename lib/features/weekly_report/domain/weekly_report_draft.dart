import 'dart:convert';

/// Lo que escribe Porty para el informe: solo prosa y referencias por id a
/// los datos. Los números, links y fuentes los pone la app.
class WeeklyReportDraft {
  const WeeklyReportDraft({
    required this.headline,
    required this.movers,
    required this.news,
    required this.investors,
    this.learn,
    this.followUpQuestion,
    this.closing,
  });

  static const empty = WeeklyReportDraft(
    headline: null,
    movers: [],
    news: [],
    investors: [],
  );

  final String? headline;
  final List<DraftMover> movers;
  final List<DraftNews> news;
  final List<DraftInvestor> investors;
  final DraftLearn? learn;
  final String? followUpQuestion;
  final String? closing;

  bool get isEmpty =>
      headline == null &&
      movers.isEmpty &&
      news.isEmpty &&
      investors.isEmpty &&
      learn == null &&
      followUpQuestion == null &&
      closing == null;

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
      headline: _text(j['headline']),
      movers: [
        for (final m in list('movers'))
          if (_text(m['ticker']) != null && _text(m['why']) != null)
            DraftMover(
              ticker: _text(m['ticker'])!.toUpperCase(),
              why: _text(m['why'])!,
              newsId: _text(m['news_id']),
            ),
      ],
      news: [
        for (final n in list('news'))
          if (_text(n['news_id']) != null && _text(n['take']) != null)
            DraftNews(newsId: _text(n['news_id'])!, take: _text(n['take'])!),
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
      followUpQuestion: _text(j['follow_up_question']),
      closing: _text(j['closing']),
    );
  }

  Map<String, Object?> toJson() => {
    'headline': headline,
    'movers': [
      for (final m in movers)
        {'ticker': m.ticker, 'why': m.why, 'news_id': m.newsId},
    ],
    'news': [
      for (final n in news) {'news_id': n.newsId, 'take': n.take},
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
    'follow_up_question': followUpQuestion,
    'closing': closing,
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

class DraftNews {
  const DraftNews({required this.newsId, required this.take});
  final String newsId;
  final String take;
}

class DraftInvestor {
  const DraftInvestor({required this.itemId, required this.take});
  final String itemId;
  final String take;
}

class DraftLearn {
  const DraftLearn({this.topic, required this.concept, required this.text});

  /// Uno de `weeklyReportLearnTopics`, de los que aplican esta semana.
  final String? topic;
  final String concept;
  final String text;
}
