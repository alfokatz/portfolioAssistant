import 'package:portfolio_assistant/features/home_widget/domain/widget_phrase.dart';

/// Qué dibuja el widget.
enum WidgetSnapshotState {
  signedOut('signed_out'),
  noPortfolio('no_portfolio'),
  ready('ready');

  const WidgetSnapshotState(this.wire);

  final String wire;
}

/// La cara de Porty del widget: contenta si sube, preocupada si baja.
enum WidgetMood {
  happy,
  concerned,
  neutral;

  static WidgetMood fromDirection(WidgetDirection direction) =>
      switch (direction) {
        WidgetDirection.up => WidgetMood.happy,
        WidgetDirection.down => WidgetMood.concerned,
        WidgetDirection.flat => WidgetMood.neutral,
      };

  String get wire => name;
}

/// Los 6 tipos de novedad del feed.
enum WidgetFeedKind {
  earnings,
  news,
  insight,
  mover,
  biggest,
  teaser;

  String get wire => name;

  static WidgetFeedKind? fromWire(String? wire) {
    for (final k in values) {
      if (k.wire == wire) return k;
    }
    return null;
  }
}

/// Un tramo de vida de una novedad: el nativo usa el último con
/// `from <= ahora`. Con posiciones ocultas solo viajan [from] y [prio].
class WidgetFeedSegment {
  const WidgetFeedSegment({
    required this.from,
    required this.prio,
    this.short,
    this.title,
    this.meta,
  });

  final DateTime from;

  /// 1 (más importante) a 3.
  final int prio;
  final String? short;
  final String? title;
  final String? meta;

  /// La misma prioridad sin textos (forma oculta).
  WidgetFeedSegment get stripped =>
      WidgetFeedSegment(from: from, prio: prio);

  Map<String, Object?> toJson() => {
    'from': from.toUtc().millisecondsSinceEpoch,
    'prio': prio,
    if (short != null) 'short': short,
    if (title != null) 'title': title,
    if (meta != null) 'meta': meta,
  };
}

/// Hacia dónde abre el toque de un ítem.
class WidgetFeedOpen {
  const WidgetFeedOpen({required this.target, this.id});

  /// 'news' | 'earnings' | 'home' | 'teaser_news' | 'teaser_earnings'.
  final String target;
  final String? id;

  Map<String, Object?> toJson() => {'target': target, if (id != null) 'id': id};
}

/// Una pregunta lista para tocar. El texto va resuelto en el idioma del
/// snapshot; [ref] busca el detalle en la caché privada de la app.
class WidgetQuestionRef {
  const WidgetQuestionRef({
    required this.ref,
    required this.template,
    required this.source,
    required this.text,
  });

  /// 8 hex.
  final String ref;

  /// `wire` de la plantilla (`news_what`, `goal_progress`, ...).
  final String template;

  /// 'novelty' | 'goal' | 'plan' | 'biggest' | 'profile'.
  final String source;
  final String text;

  Map<String, Object?> toJson() => {
    'ref': ref,
    't': template,
    'src': source,
    'text': text,
  };
}

/// Una novedad del feed (schema v2, docs/specs/home-widget-v2-tech.md §3.2).
class WidgetFeedItem {
  const WidgetFeedItem({
    required this.kind,
    required this.icon,
    required this.expiresAt,
    required this.segments,
    this.id,
    this.tag,
    this.paid = false,
    this.publishedAt,
    this.a11y,
    this.open,
    this.q,
  });

  final WidgetFeedKind kind;

  /// 'calendar' | 'news' | 'pie' | 'chart'.
  final String icon;
  final DateTime expiresAt;
  final List<WidgetFeedSegment> segments;

  /// 8 hex, opaco. `null` en la forma oculta.
  final String? id;
  final String? tag;

  /// Traído con el plan pago: el nativo lo saca pasado `plan_until`.
  final bool paid;
  final DateTime? publishedAt;
  final String? a11y;
  final WidgetFeedOpen? open;
  final WidgetQuestionRef? q;

  /// El segmento vigente a la hora [now] (el primero si ninguno arrancó).
  WidgetFeedSegment segmentAt(DateTime now) {
    var current = segments.first;
    for (final s in segments) {
      if (!s.from.isAfter(now)) current = s;
    }
    return current;
  }

  int prioAt(DateTime now) => segmentAt(now).prio;

  /// Sin ticker, titular, fuente, meta ni id: solo qué clase de cosa es,
  /// cuándo vence y su prioridad. Para "Ocultar posiciones".
  WidgetFeedItem get hiddenForm => WidgetFeedItem(
    kind: kind,
    icon: icon,
    expiresAt: expiresAt,
    paid: paid,
    segments: [for (final s in segments) s.stripped],
  );

  Map<String, Object?> toJson() => {
    if (id != null) 'id': id,
    'kind': kind.wire,
    'icon': icon,
    if (tag != null) 'tag': tag,
    if (paid) 'paid': true,
    if (publishedAt != null)
      'published_at': publishedAt!.toUtc().millisecondsSinceEpoch,
    'expires_at': expiresAt.toUtc().millisecondsSinceEpoch,
    'segments': [for (final s in segments) s.toJson()],
    if (a11y != null) 'a11y': a11y,
    if (open != null) 'open': open!.toJson(),
    if (q != null) 'q': q!.toJson(),
  };
}

/// Forma normalizada del día (o de los últimos días): 0..1, sin montos.
class WidgetChart {
  const WidgetChart({required this.kind, required this.points, this.baseline});

  /// 'intraday' | 'days'.
  final String kind;
  final List<double> points;

  /// Cierre anterior (línea punteada); `null` en 'days'.
  final double? baseline;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'points': points,
    'baseline': baseline,
  };
}

class WidgetQuestions {
  const WidgetQuestions({this.fallback, this.large = const []});

  /// La del mediano cuando el ítem no trae `q`.
  final WidgetQuestionRef? fallback;

  /// 0..2 para el grande.
  final List<WidgetQuestionRef> large;

  Map<String, Object?> toJson() => {
    'fallback': fallback?.toJson(),
    'large': [for (final q in large) q.toJson()],
  };
}

/// El bloque `v2`: su presencia (objeto) = layout v2.
class WidgetV2Block {
  const WidgetV2Block({
    required this.positionsHidden,
    required this.mood,
    required this.labels,
    this.planUntil,
    this.chart,
    this.feedRev,
    this.feed = const [],
    this.questions = const WidgetQuestions(),
  });

  final bool positionsHidden;
  final WidgetMood mood;
  final DateTime? planUntil;
  final WidgetChart? chart;

  /// FNV-1a de los ids en orden. Ausente con posiciones ocultas.
  final String? feedRev;
  final List<WidgetFeedItem> feed;
  final WidgetQuestions questions;
  final Map<String, String> labels;

  Map<String, Object?> toJson() => {
    'positions_hidden': positionsHidden,
    'mood': mood.wire,
    'plan_until': planUntil?.toUtc().millisecondsSinceEpoch,
    'chart': chart?.toJson(),
    if (feedRev != null) 'feed_rev': feedRev,
    'feed': [for (final i in feed) i.toJson()],
    'questions': questions.toJson(),
    'labels': labels,
  };
}

/// Lo que Flutter le deja al widget nativo: un único JSON con todo ya
/// armado (docs/specs/home-widget-v2-tech.md §3). El widget solo lo dibuja,
/// filtra por hora y avanza el cursor del mediano.
///
/// `v` sigue en 1. El bloque v1 es compatible hacia atrás y NUNCA lleva
/// montos, valor total, ticker en la frase ni preguntas: `amounts_hidden`
/// va siempre en `true`. Todo lo nuevo vive en [v2].
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.state,
    required this.lang,
    required this.writtenAt,
    required this.labels,
    this.dataAsOf,
    this.staleAt,
    this.period,
    this.changePctText,
    this.direction,
    this.phrase,
    this.phraseStale,
    this.a11yValue,
    this.v2,
  });

  static const schemaVersion = 1;

  /// Clave del almacenamiento compartido.
  static const storageKey = 'porty_widget_snapshot';

  final WidgetSnapshotState state;

  /// 'es' | 'en'.
  final String lang;
  final DateTime writtenAt;
  final DateTime? dataAsOf;
  final DateTime? staleAt;

  /// 'today' | 'last_close' (solo `ready`).
  final String? period;
  final String? changePctText;
  final WidgetDirection? direction;
  final String? phrase;
  final String? phraseStale;
  final String? a11yValue;
  final Map<String, String> labels;

  /// Solo `ready`.
  final WidgetV2Block? v2;

  WidgetSnapshot copyWith({WidgetV2Block? v2}) => WidgetSnapshot(
    state: state,
    lang: lang,
    writtenAt: writtenAt,
    labels: labels,
    dataAsOf: dataAsOf,
    staleAt: staleAt,
    period: period,
    changePctText: changePctText,
    direction: direction,
    phrase: phrase,
    phraseStale: phraseStale,
    a11yValue: a11yValue,
    v2: v2 ?? this.v2,
  );

  Map<String, Object?> toJson() => {
    'v': schemaVersion,
    'state': state.wire,
    'lang': lang,
    'written_at': writtenAt.toUtc().millisecondsSinceEpoch,
    if (dataAsOf != null)
      'data_as_of': dataAsOf!.toUtc().millisecondsSinceEpoch,
    if (staleAt != null) 'stale_at': staleAt!.toUtc().millisecondsSinceEpoch,
    if (period != null) 'period': period,
    // Desde v2 el widget nunca muestra montos: un nativo viejo que lea
    // este bloque dibuja "••••" y el %, sin ticker.
    if (state == WidgetSnapshotState.ready) 'amounts_hidden': true,
    if (state == WidgetSnapshotState.ready) 'currency': 'USD',
    if (changePctText != null) 'change_pct_text': changePctText,
    if (direction != null) 'direction': direction!.wire,
    if (phrase != null) 'phrase': phrase,
    if (phraseStale != null) 'phrase_stale': phraseStale,
    if (a11yValue != null) 'a11y_value': a11yValue,
    'labels': labels,
    if (state == WidgetSnapshotState.ready && v2 != null) 'v2': v2!.toJson(),
  };
}
