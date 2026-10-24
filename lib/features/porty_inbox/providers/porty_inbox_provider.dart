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
    hidden: ref.read(portyInboxHiddenProvider.notifier).activeIds,
  );
});
