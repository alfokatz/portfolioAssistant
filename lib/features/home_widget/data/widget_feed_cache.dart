import 'dart:convert';

import 'package:portfolio_assistant/features/home_widget/domain/widget_feed_order.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_insight_copy.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_portfolio_facts.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_questions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_json.dart';

/// Lo que se recuerda de una pregunta mostrada, para resolver el `ref` que
/// toca el usuario aunque el widget dibuje un snapshot anterior.
class WidgetCachedQuestion {
  const WidgetCachedQuestion({
    required this.template,
    required this.args,
    required this.hidden,
    required this.seenAt,
  });

  final WidgetQuestionTemplate template;
  final Map<String, String> args;
  final bool hidden;
  final DateTime seenAt;

  Map<String, Object?> toJson() => {
    't': template.wire,
    'args': args,
    'hidden': hidden,
    'seen_at': seenAt.toUtc().millisecondsSinceEpoch,
  };

  static WidgetCachedQuestion? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final template = WidgetQuestionTemplate.fromWire(raw['t'] as String?);
    final seen = raw['seen_at'];
    if (template == null || seen is! num) return null;
    final args = raw['args'];
    return WidgetCachedQuestion(
      template: template,
      args: {
        if (args is Map)
          for (final e in args.entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
      },
      hidden: raw['hidden'] == true,
      seenAt: DateTime.fromMillisecondsSinceEpoch(seen.toInt(), isUtc: true),
    );
  }
}

/// Lo último que la app abierta supo y el refresco de fondo (sin sesión)
/// necesita para rearmar el feed: avisos, meta, plan, perfil y posición más
/// grande. Caché PRIVADA (docs/specs/home-widget-v2-tech.md §3.6).
class WidgetFeedCacheEntry {
  const WidgetFeedCacheEntry({
    required this.uid,
    required this.writtenAt,
    this.insights = const [],
    this.goalLabel,
    this.driftTicker,
    this.profileRisk,
    this.biggest,
    this.questions = const {},
  });

  final String uid;
  final DateTime writtenAt;
  final List<WidgetInsightInput> insights;
  final String? goalLabel;

  /// `null` = no hay desvío del plan; `''` = hay desvío sin ticker.
  final String? driftTicker;
  final String? profileRisk;
  final WidgetBiggestFact? biggest;

  /// Por `ref`, las de las últimas 24 h.
  final Map<String, WidgetCachedQuestion> questions;

  /// Los avisos viejos no se usan (se recalculan al abrir la app).
  static const maxAge = Duration(hours: 24);

  bool isFresh(DateTime now) => now.difference(writtenAt) <= maxAge;

  WidgetFeedCacheEntry copyWith({
    Map<String, WidgetCachedQuestion>? questions,
  }) => WidgetFeedCacheEntry(
    uid: uid,
    writtenAt: writtenAt,
    insights: insights,
    goalLabel: goalLabel,
    driftTicker: driftTicker,
    profileRisk: profileRisk,
    biggest: biggest,
    questions: questions ?? this.questions,
  );

  Map<String, Object?> toJson() => {
    'uid': uid,
    'written_at': writtenAt.toUtc().millisecondsSinceEpoch,
    'insights': [for (final i in insights) i.toJson()],
    if (goalLabel != null) 'goal': {'label': goalLabel},
    if (driftTicker != null) 'drift_ticker': driftTicker,
    if (profileRisk != null) 'profile_risk': profileRisk,
    if (biggest != null)
      'biggest': {'ticker': biggest!.ticker, 'weight': biggest!.weightPct},
    'questions': {
      for (final e in questions.entries) e.key: e.value.toJson(),
    },
  };

  static WidgetFeedCacheEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final uid = raw['uid'];
    final written = raw['written_at'];
    if (uid is! String || written is! num) return null;
    final goal = raw['goal'];
    final big = raw['biggest'];
    final questions = raw['questions'];
    return WidgetFeedCacheEntry(
      uid: uid,
      writtenAt: DateTime.fromMillisecondsSinceEpoch(
        written.toInt(),
        isUtc: true,
      ),
      insights: [
        for (final i in (raw['insights'] as List? ?? const []))
          if (i is Map)
            if (WidgetInsightInput.fromJson(i.cast<String, Object?>())
                case final insight?)
              insight,
      ],
      goalLabel: goal is Map ? goal['label'] as String? : null,
      driftTicker: raw['drift_ticker'] as String?,
      profileRisk: raw['profile_risk'] as String?,
      biggest:
          big is Map && big['ticker'] is String && big['weight'] is num
              ? WidgetBiggestFact(
                ticker: big['ticker'] as String,
                weightPct: (big['weight'] as num).toDouble(),
              )
              : null,
      questions: {
        if (questions is Map)
          for (final e in questions.entries)
            if (e.key is String)
              if (WidgetCachedQuestion.fromJson(e.value) case final q?)
                e.key as String: q,
      },
    );
  }
}

/// `widget_feed_cache_v1` y `widget_feed_state_v1` en las preferencias
/// PRIVADAS de la app. Uid distinto = como si no hubiera.
class WidgetFeedCache {
  const WidgetFeedCache(this._prefs);

  static const cacheKey = 'widget_feed_cache_v1';
  static const stateKey = 'widget_feed_state_v1';

  final SharedPreferences _prefs;

  WidgetFeedCacheEntry? read({required String uid}) {
    final raw = _prefs.getString(cacheKey);
    if (raw == null) return null;
    try {
      final entry = WidgetFeedCacheEntry.fromJson(jsonDecode(raw));
      return entry != null && entry.uid == uid ? entry : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(WidgetFeedCacheEntry entry) =>
      _prefs.setString(cacheKey, jsonEncode(widgetJsonSafe(entry.toJson())));

  /// Suma [drafts] a las preguntas recordadas y poda las de más de 24 h.
  Future<void> rememberQuestions({
    required String uid,
    required List<WidgetQuestionDraft> drafts,
    required bool hidden,
    required DateTime now,
  }) async {
    final current = read(uid: uid);
    if (current == null) return;
    final merged = <String, WidgetCachedQuestion>{
      for (final e in current.questions.entries)
        if (now.difference(e.value.seenAt) <= WidgetFeedCacheEntry.maxAge)
          e.key: e.value,
      for (final d in drafts)
        d.ref(hidden: hidden): WidgetCachedQuestion(
          template: d.template,
          args: d.args,
          hidden: hidden,
          seenAt: now,
        ),
    };
    await write(current.copyWith(questions: merged));
  }

  /// La pregunta detrás de [ref], si es de este usuario y sigue guardada.
  WidgetCachedQuestion? question({required String uid, required String ref}) =>
      read(uid: uid)?.questions[ref];

  WidgetFeedState readState({required String uid}) {
    final raw = _prefs.getString(stateKey);
    if (raw == null) return const WidgetFeedState();
    try {
      final json = jsonDecode(raw);
      if (json is! Map || json['uid'] != uid) return const WidgetFeedState();
      return WidgetFeedState.fromJson(json.cast<String, Object?>());
    } catch (_) {
      return const WidgetFeedState();
    }
  }

  Future<void> writeState({
    required String uid,
    required WidgetFeedState state,
  }) => _prefs.setString(
    stateKey,
    jsonEncode(widgetJsonSafe({'uid': uid, ...state.toJson()})),
  );

  Future<void> clear() async {
    await _prefs.remove(cacheKey);
    await _prefs.remove(stateKey);
  }
}
