/// Los planes que Porty calculó en la conversación, para que la compra
/// mensual parta del plan que el usuario está viendo (el modelo pasa el
/// `plan_id`; las tools no ven resultados de turnos anteriores).
///
/// También recuerda el rendimiento por dividendos real de la última compra
/// mensual: los planes siguientes lo usan en vez del supuesto fijo.
class SavingsPlanStore {
  final _results = <String, Map<String, Object?>>{};
  String? _lastPlanId;

  /// Rendimiento por dividendos (fracción) de la última compra mensual con
  /// datos suficientes; `null` = se usa el supuesto.
  double? dividendYield;

  void record(String planId, Map<String, Object?> result) {
    _results[planId] = result;
    _lastPlanId = planId;
  }

  /// El plan [planId], o el último si no se pasa (o no existe).
  Map<String, Object?>? lookup(String? planId) =>
      (planId == null ? null : _results[planId]) ??
      (_lastPlanId == null ? null : _results[_lastPlanId]);
}
