import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/home_widget/data/home_widget_store.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_settings_provider.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Las reglas de cuándo ofrecer "Tené a Porty en tu pantalla de inicio".
/// Puras: todo entra por parámetro.
abstract final class WidgetPromptRules {
  /// Desde qué apertura se ofrece (la 3.ª).
  static const minOpens = 3;

  /// Tras una oferta (cerrada o no), cuánto se espera para otra.
  static const cooldown = Duration(days: 30);

  /// Máximo de ofertas automáticas en total.
  static const maxOffers = 2;

  static bool shouldOffer({
    required int opens,
    required int offersShown,
    required DateTime? lastOfferAt,
    required DateTime now,
    required bool installed,
    required bool hasPortfolio,
    required bool offeredThisOpen,
  }) {
    if (installed || !hasPortfolio || offeredThisOpen) return false;
    if (opens < minOpens || offersShown >= maxOffers) return false;
    if (lastOfferAt != null && now.difference(lastOfferAt) < cooldown) {
      return false;
    }
    return true;
  }
}

class WidgetPromptState {
  const WidgetPromptState({
    this.opens = 0,
    this.offersShown = 0,
    this.lastOfferAt,
    this.offeredThisOpen = false,
  });

  final int opens;
  final int offersShown;
  final DateTime? lastOfferAt;

  /// Ya se ofreció en esta apertura (se reinicia al contar otra).
  final bool offeredThisOpen;

  WidgetPromptState copyWith({
    int? opens,
    int? offersShown,
    DateTime? lastOfferAt,
    bool? offeredThisOpen,
  }) => WidgetPromptState(
    opens: opens ?? this.opens,
    offersShown: offersShown ?? this.offersShown,
    lastOfferAt: lastOfferAt ?? this.lastOfferAt,
    offeredThisOpen: offeredThisOpen ?? this.offeredThisOpen,
  );
}

/// Guarda en el `SharedPreferences` privado cuántas aperturas hubo y cuándo
/// se ofreció (se borra al cerrar sesión, ver `HomeWidgetSyncController`).
class WidgetPromptNotifier extends StateNotifier<WidgetPromptState> {
  WidgetPromptNotifier(this._prefs, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(_read(_prefs));

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  static WidgetPromptState _read(SharedPreferences prefs) {
    final at = prefs.getInt(WidgetPrefsKeys.promptLastAt);
    return WidgetPromptState(
      opens: prefs.getInt(WidgetPrefsKeys.promptOpens) ?? 0,
      offersShown: prefs.getInt(WidgetPrefsKeys.promptShown) ?? 0,
      lastOfferAt: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
    );
  }

  /// Vuelve a leer lo guardado (otra sesión en el mismo proceso).
  void reload() => state = _read(_prefs);

  /// Una apertura más de la app: habilita una oferta nueva.
  Future<void> registerOpen() async {
    state = state.copyWith(opens: state.opens + 1, offeredThisOpen: false);
    await _prefs.setInt(WidgetPrefsKeys.promptOpens, state.opens);
  }

  /// Se va a mostrar la oferta automática: cuenta ya (si la app se cierra
  /// con la hoja abierta, igual vale).
  Future<void> markShown() async {
    final now = _now();
    state = state.copyWith(
      offersShown: state.offersShown + 1,
      lastOfferAt: now,
      offeredThisOpen: true,
    );
    await _prefs.setInt(WidgetPrefsKeys.promptShown, state.offersShown);
    await _prefs.setInt(
      WidgetPrefsKeys.promptLastAt,
      now.millisecondsSinceEpoch,
    );
  }

  bool shouldOffer({required bool installed, required bool hasPortfolio}) =>
      WidgetPromptRules.shouldOffer(
        opens: state.opens,
        offersShown: state.offersShown,
        lastOfferAt: state.lastOfferAt,
        now: _now(),
        installed: installed,
        hasPortfolio: hasPortfolio,
        offeredThisOpen: state.offeredThisOpen,
      );
}

final widgetPromptProvider =
    StateNotifierProvider<WidgetPromptNotifier, WidgetPromptState>(
      (ref) => WidgetPromptNotifier(ref.watch(sharedPreferencesProvider)),
    );

/// Los tamaños del widget instalados hoy. Si el plugin falla, ninguno.
final widgetInstalledSizesProvider =
    FutureProvider.autoDispose<InstalledWidgetSizes>((ref) async {
      try {
        return await ref.watch(homeWidgetStoreProvider).installedSizes();
      } catch (_) {
        return const [];
      }
    });

/// Lo que dibuja la vista previa de la hoja, sacado del snapshot real. `null`
/// = no hay datos: se muestra una vista ilustrativa (sin números inventados).
class WidgetPreviewData {
  const WidgetPreviewData({
    required this.total,
    required this.period,
    this.change,
    this.changePct,
    this.direction,
    this.phrase,
  });

  final String total;
  final String? period;
  final String? change;
  final String? changePct;

  /// 'up' | 'down' | 'flat'.
  final String? direction;
  final String? phrase;

  /// `null` si el snapshot no es un `ready` con datos.
  static WidgetPreviewData? fromSnapshotJson(Map<String, Object?>? json) {
    if (json == null || json['state'] != 'ready') return null;
    final labels = json['labels'];
    final l = labels is Map ? labels : const {};
    final hidden = json['amounts_hidden'] == true;
    final total =
        hidden ? l['hidden_amount'] : json['total_text'] ?? l['hidden_amount'];
    final pct = json['change_pct_text'];
    if (total is! String || pct is! String) return null;
    final period = l['period_${json['period']}'];
    return WidgetPreviewData(
      total: total,
      period: period is String ? period : null,
      change:
          json['change_text'] is String ? json['change_text'] as String : null,
      changePct: pct,
      direction:
          json['direction'] is String ? json['direction'] as String : null,
      phrase: json['phrase'] is String ? json['phrase'] as String : null,
    );
  }
}

final widgetPreviewProvider = FutureProvider.autoDispose<WidgetPreviewData?>((
  ref,
) async {
  try {
    final json = await ref.watch(homeWidgetStoreProvider).readSnapshotJson();
    return WidgetPreviewData.fromSnapshotJson(json);
  } catch (_) {
    return null;
  }
});
