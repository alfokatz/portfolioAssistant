/// Los planes que Porty calculó en la conversación, para que la compra
/// mensual parta del plan que el usuario está viendo (el modelo pasa el
/// `plan_id`; las tools no ven resultados de turnos anteriores).
///
/// También recuerda el rendimiento por dividendos real de la última compra
/// mensual: los planes siguientes lo usan en vez del supuesto fijo.
///
/// Si el usuario editó un plan en su card, la edición queda acá bajo el id
/// del plan original: lo que Porty haga después con ese plan ("hacelo en 2
/// años", la compra mensual) parte de lo que el usuario ve.
class SavingsPlanStore {
  final _results = <String, Map<String, Object?>>{};
  final _edits = <String, String>{};
  String? _lastPlanId;

  /// Rendimiento por dividendos (fracción) de la última compra mensual con
  /// datos suficientes; `null` = se usa el supuesto.
  double? dividendYield;

  void record(String planId, Map<String, Object?> result) {
    _results[planId] = result;
    _lastPlanId = planId;
  }

  /// El plan [planId] (con la edición del usuario, si la hay), o el último
  /// si no se pasa (o no existe).
  Map<String, Object?>? lookup(String? planId) {
    final id = planId == null ? null : (_edits[planId] ?? planId);
    return (id == null ? null : _results[id]) ??
        (_lastPlanId == null ? null : _results[_lastPlanId]);
  }

  /// El usuario editó en la card el plan [originalId]: [edited] es el
  /// resultado recalculado (con su propio `plan_id`).
  void recordEdit(
    String originalId,
    String editedId,
    Map<String, Object?> edited,
  ) {
    _results[editedId] = edited;
    _edits[originalId] = editedId;
    _lastPlanId = editedId;
  }

  /// Deshace la edición del plan [originalId].
  void clearEdit(String originalId) {
    _edits.remove(originalId);
    if (_results.containsKey(originalId)) _lastPlanId = originalId;
  }

  /// La edición del usuario del plan [originalId], si la hay.
  Map<String, Object?>? editOf(String originalId) {
    final id = _edits[originalId];
    return id == null ? null : _results[id];
  }
}
