/// Contador del análisis Gold de cortesía semanal (vive en el servidor).
abstract class WeeklyFreeAnalysisRepository {
  /// `true` si el usuario todavía tiene su análisis gratis de [weekStart].
  /// Ante cualquier falla, `false`: mejor no ofrecer que ofrecer y fallar.
  Future<bool> isAvailable(String weekStart);

  /// Gasta la cortesía de [weekStart]. `true` solo si ESTA llamada la gastó
  /// (atómico en el servidor: dos pedidos en paralelo no la usan dos veces).
  Future<bool> consume(String weekStart, {String? ticker});
}
