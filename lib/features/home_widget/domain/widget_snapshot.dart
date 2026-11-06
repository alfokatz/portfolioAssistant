import 'package:portfolio_assistant/features/home_widget/domain/widget_launch.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_phrase.dart';

/// Qué dibuja el widget.
enum WidgetSnapshotState {
  signedOut('signed_out'),
  noPortfolio('no_portfolio'),
  ready('ready');

  const WidgetSnapshotState(this.wire);

  final String wire;
}

class WidgetQuestion {
  const WidgetQuestion({required this.id, required this.text});

  final WidgetQuestionId id;
  final String text;

  Map<String, Object?> toJson() => {'id': id.wire, 'text': text};
}

/// Un ítem de "Novedades de tu cartera": una noticia o una fecha estimada de
/// resultados. Nunca lleva la URL del artículo (vive en la caché privada).
class WidgetItem {
  const WidgetItem.news({
    required this.id,
    required this.ticker,
    required this.source,
    required this.headline,
    required DateTime this.publishedAt,
    required this.expiresAt,
  }) : kind = 'news',
       segments = const [],
       a11y = null;

  const WidgetItem.earnings({
    required this.id,
    required this.ticker,
    required this.segments,
    required String this.a11y,
    required this.expiresAt,
  }) : kind = 'earnings',
       source = null,
       headline = null,
       publishedAt = null;

  /// 8 hex, opaco.
  final String id;

  /// 'news' | 'earnings'.
  final String kind;
  final String ticker;
  final String? source;
  final String? headline;
  final DateTime? publishedAt;
  final DateTime expiresAt;

  /// Solo resultados: el nativo usa el último con `from <= now`.
  final List<WidgetItemSegment> segments;
  final String? a11y;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'ticker': ticker,
    if (source != null) 'source': source,
    if (headline != null) 'headline': headline,
    if (publishedAt != null)
      'published_at': publishedAt!.toUtc().millisecondsSinceEpoch,
    if (segments.isNotEmpty) 'segments': [for (final s in segments) s.toJson()],
    if (a11y != null) 'a11y': a11y,
    'expires_at': expiresAt.toUtc().millisecondsSinceEpoch,
  };
}

class WidgetItemSegment {
  const WidgetItemSegment({required this.from, required this.text});

  final DateTime from;
  final String text;

  Map<String, Object?> toJson() => {
    'from': from.toUtc().millisecondsSinceEpoch,
    'text': text,
  };
}

/// Aviso del plan siguiente. El texto ya viene elegido por plataforma.
class WidgetTeaser {
  const WidgetTeaser({
    required this.kind,
    required this.text,
    this.count,
    this.medium = false,
  });

  /// 'news' | 'earnings'.
  final String kind;
  final String text;

  /// `null` en el aviso sin número.
  final int? count;

  /// Si entra en el mediano (solo con noticias de las últimas 24 h).
  final bool medium;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'text': text,
    'count': count,
    if (medium) 'medium': true,
  };
}

/// Lo que Flutter le deja al widget nativo: un único JSON (schema v1, ver
/// docs/specs/home-widget-tech.md §3.2) con todo ya armado. El widget solo
/// lo dibuja, calcula "hace X" y compara la hora con [staleAt].
///
/// Nunca lleva tokens, user id, email, cantidades ni la lista de
/// tenencias. Con [amountsHidden], los montos y el ticker no están
/// (ausentes, no escondidos).
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.state,
    required this.lang,
    required this.writtenAt,
    required this.labels,
    this.dataAsOf,
    this.staleAt,
    this.period,
    this.amountsHidden = false,
    this.totalText,
    this.changeText,
    this.changePctText,
    this.direction,
    this.phrase,
    this.phraseStale,
    this.a11yValue,
    this.questions = const [],
    this.itemsSection,
    this.itemsCheckedAt,
    this.planUntil,
    this.items = const [],
    this.teaser,
    this.itemsLabels,
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
  final bool amountsHidden;
  final String? totalText;
  final String? changeText;
  final String? changePctText;
  final WidgetDirection? direction;
  final String? phrase;
  final String? phraseStale;
  final String? a11yValue;
  final Map<String, String> labels;
  final List<WidgetQuestion> questions;

  /// Ampliación (solo `ready`). `null` = no hay bloque (como el v1).
  final bool? itemsSection;
  final DateTime? itemsCheckedAt;
  final DateTime? planUntil;
  final List<WidgetItem> items;
  final WidgetTeaser? teaser;
  final Map<String, String>? itemsLabels;

  WidgetSnapshot copyWith({
    bool? itemsSection,
    DateTime? itemsCheckedAt,
    DateTime? planUntil,
    List<WidgetItem>? items,
    WidgetTeaser? teaser,
    Map<String, String>? itemsLabels,
  }) => WidgetSnapshot(
    state: state,
    lang: lang,
    writtenAt: writtenAt,
    labels: labels,
    dataAsOf: dataAsOf,
    staleAt: staleAt,
    period: period,
    amountsHidden: amountsHidden,
    totalText: totalText,
    changeText: changeText,
    changePctText: changePctText,
    direction: direction,
    phrase: phrase,
    phraseStale: phraseStale,
    a11yValue: a11yValue,
    questions: questions,
    itemsSection: itemsSection ?? this.itemsSection,
    itemsCheckedAt: itemsCheckedAt ?? this.itemsCheckedAt,
    planUntil: planUntil ?? this.planUntil,
    items: items ?? this.items,
    teaser: teaser ?? this.teaser,
    itemsLabels: itemsLabels ?? this.itemsLabels,
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
    if (state == WidgetSnapshotState.ready) 'amounts_hidden': amountsHidden,
    if (state == WidgetSnapshotState.ready) 'currency': 'USD',
    if (totalText != null) 'total_text': totalText,
    if (changeText != null) 'change_text': changeText,
    if (changePctText != null) 'change_pct_text': changePctText,
    if (direction != null) 'direction': direction!.wire,
    if (phrase != null) 'phrase': phrase,
    if (phraseStale != null) 'phrase_stale': phraseStale,
    if (a11yValue != null) 'a11y_value': a11yValue,
    'labels': labels,
    if (questions.isNotEmpty)
      'questions': [for (final q in questions) q.toJson()],
    if (state == WidgetSnapshotState.ready && itemsSection != null) ...{
      'items_section': itemsSection,
      if (itemsCheckedAt != null)
        'items_checked_at': itemsCheckedAt!.toUtc().millisecondsSinceEpoch,
      'plan_until': planUntil?.toUtc().millisecondsSinceEpoch,
      'items': [for (final i in items) i.toJson()],
      'teaser': teaser?.toJson(),
      if (itemsLabels != null) 'items_labels': itemsLabels,
    },
  };
}
