import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/allocation/providers/allocation_provider.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/features/notifications/providers/price_alerts_provider.dart';
import 'package:portfolio_assistant/features/porty_inbox/domain/porty_insight.dart';
import 'package:portfolio_assistant/features/porty_inbox/domain/porty_insights_builder.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';
import 'package:portfolio_assistant/features/porty_memory/providers/porty_topics_provider.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/porty_topic.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';

const portyInboxHiddenKey = 'porty_inbox_hidden';

/// Lo que el usuario ocultó de la bandeja ("ya lo vi"), con la fecha: vuelve
/// a aparecer pasados [hideFor] si sigue siendo cierto. Vive en el teléfono;
/// sin preferencias (tests), en memoria.
class PortyInboxHiddenNotifier extends StateNotifier<Map<String, DateTime>> {
  PortyInboxHiddenNotifier(this._prefs, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(const {}) {
    state = _read();
  }

  final SharedPreferences? _prefs;
  final DateTime Function() _now;

  static const hideFor = Duration(days: 7);

  Map<String, DateTime> _read() {
    try {
      final raw = _prefs?.getString(portyInboxHiddenKey);
      if (raw == null) return const {};
      final decoded = (jsonDecode(raw) as Map).cast<String, Object?>();
      final limit = _now().subtract(hideFor);
      return {
        for (final MapEntry(:key, :value) in decoded.entries)
          if (DateTime.tryParse('$value') case final at? when at.isAfter(limit))
            key: at,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Los ids que siguen ocultos hoy.
  Set<String> get activeIds {
    final limit = _now().subtract(hideFor);
    return {
      for (final MapEntry(:key, :value) in state.entries)
        if (value.isAfter(limit)) key,
    };
  }

  Future<void> hide(String id) async {
    state = {...state, id: _now()};
    try {
      await _prefs?.setString(
        portyInboxHiddenKey,
        jsonEncode({
          for (final MapEntry(:key, :value) in state.entries)
            key: value.toIso8601String(),
        }),
      );
    } catch (_) {}
  }
}

final portyInboxHiddenProvider =
    StateNotifierProvider<PortyInboxHiddenNotifier, Map<String, DateTime>>((
      ref,
    ) {
      SharedPreferences? prefs;
      try {
        prefs = ref.watch(sharedPreferencesProvider);
      } catch (_) {
        // Sin override (tests de otras pantallas): en memoria.
      }
      return PortyInboxHiddenNotifier(prefs);
    });

/// El precio de hoy de los temas de charla que pueden haberse movido: de
/// los últimos 30 días, con al menos 2 días (antes no hubo tiempo de que
/// pase nada), que el usuario no tiene (lo que tiene lo cubre la cartera) y
/// con el precio de ese día. Hasta 3, en paralelo; lo que falla, no está.
final portyTopicPricesProvider = FutureProvider<List<TopicPrice>>((ref) async {
  // Precios de lo que no tiene: Premium (como en el chat).
  final tier = ref.watch(subscriptionProvider.select((s) => s.tier));
  if (!SubscriptionPolicy.allows(tier, PlanFeature.marketData)) return const [];
  final topics = ref.watch(portyTopicsProvider.select((s) => s.topics));
  final held = {
    for (final v
        in ref.watch(homeProvider.select((s) => s.summary))?.valuations ??
            const [])
      v.position.ticker.toUpperCase(),
  };
  final now = DateTime.now();
  final candidates =
      [
        for (final t in topics)
          if (!held.contains(t.ticker) &&
              t.priceAt != null &&
              now.difference(t.lastAskedAt) >= const Duration(days: 2) &&
              now.difference(t.lastAskedAt) <= PortyTopic.briefWindow)
            t,
      ].take(3).toList();
  if (candidates.isEmpty) return const [];
  final quotes = ref.watch(quoteRepositoryProvider);
  final prices = await Future.wait(
    candidates.map(
      (t) => quotes
          .getCurrentPrice(t.ticker)
          .then((r) => r.fold<double?>((_) => null, (p) => p > 0 ? p : null))
          .catchError((Object _) => null),
    ),
  );
  return [
    for (final (i, t) in candidates.indexed)
      if (prices[i] case final price?) (topic: t, price: price),
  ];
});

/// Lo que Porty marca hoy en la Home, ya ordenado y sin lo oculto.
final portyInsightsProvider = Provider<List<PortyInsight>>((ref) {
  final summary = ref.watch(homeProvider.select((s) => s.summary));
  ref.watch(portyInboxHiddenProvider);
  return PortyInsightsBuilder.build(
    summary: summary,
    now: DateTime.now(),
    drift: ref.watch(allocationDriftProvider),
    goals: ref.watch(goalsProvider.select((s) => s.goals)),
    holdings: ref.watch(goalHoldingsProvider),
    alerts: ref.watch(priceAlertsProvider.select((s) => s.alerts)),
    topicPrices: ref.watch(portyTopicPricesProvider).valueOrNull ?? const [],
    hidden: ref.read(portyInboxHiddenProvider.notifier).activeIds,
  );
});
