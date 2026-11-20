import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/notifications/data/price_alerts_repository.dart';
import 'package:portfolio_assistant/features/notifications/domain/price_alert.dart';

class PriceAlertsState {
  const PriceAlertsState({
    this.alerts = const [],
    this.loaded = false,
    this.loadFailed = false,
  });

  final List<PriceAlert> alerts;
  final bool loaded;
  final bool loadFailed;

  List<PriceAlert> get active =>
      alerts.where((a) => a.status == PriceAlertStatus.active).toList();

  int get activeCount => active.length;

  List<PriceAlert> forSymbol(String symbol) =>
      alerts.where((a) => a.symbol == symbol.toUpperCase()).toList();
}

class PriceAlertsNotifier extends StateNotifier<PriceAlertsState> {
  PriceAlertsNotifier(this._repo) : super(const PriceAlertsState());

  final PriceAlertsRepository _repo;

  Future<void> load() async {
    try {
      final alerts = await _repo.list();
      if (mounted) state = PriceAlertsState(alerts: alerts, loaded: true);
    } catch (e) {
      debugPrint('[PriceAlerts] load: $e');
      if (mounted) {
        state = PriceAlertsState(
          alerts: state.alerts,
          loaded: true,
          loadFailed: true,
        );
      }
    }
  }

  /// Crea la alerta. Tira [PriceAlertFailure] (tope del plan, inválida,
  /// sin red).
  Future<PriceAlert> create(PriceAlertDraft draft) async {
    final alert = await _repo.create(draft);
    if (mounted) {
      state = PriceAlertsState(alerts: [alert, ...state.alerts], loaded: true);
    }
    return alert;
  }

  Future<void> setActive(PriceAlert alert, {required bool active}) async {
    await _repo.setActive(alert.id, active: active);
    await load();
  }

  Future<void> delete(PriceAlert alert) async {
    final previous = state.alerts;
    state = PriceAlertsState(
      alerts: previous.where((a) => a.id != alert.id).toList(),
      loaded: true,
    );
    try {
      await _repo.delete(alert.id);
    } catch (e) {
      if (mounted) state = PriceAlertsState(alerts: previous, loaded: true);
      rethrow;
    }
  }
}

final priceAlertsProvider =
    StateNotifierProvider<PriceAlertsNotifier, PriceAlertsState>(
      (ref) => PriceAlertsNotifier(ref.watch(priceAlertsRepositoryProvider)),
    );
