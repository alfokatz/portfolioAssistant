/// Único corte previo al modelo del pipeline unificado: el mensaje pidió
/// tickers y TODOS fallaron (sin ningún dato real que mostrar). Todo lo
/// demás — conceptual, sin ticker, cartera vacía — lo responde el modelo
/// con las reglas unificadas, en vez de cortar con un error técnico.
abstract final class UnifiedSnapshotValidator {
  static bool allRequestedTickersFailed(Map<String, dynamic> snapshot) {
    if (snapshot['ticker_ambiguous'] != null) return false;
    final tickers = snapshot['tickers'];
    if (tickers is! Map || tickers.isEmpty) return false;
    return !tickers.values.any((t) => t is Map && t['fetch_ok'] == true);
  }
}
