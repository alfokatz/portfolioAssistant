/// Calcula fit_score (0–100) para un candidato de inversión simulada.
///
/// Fórmula:
/// - 40% diversificación: 40 si el sector del candidato difiere del sector
///   sobrepeso del portfolio; si coincide, 40 × (1 − pesoSector/100).
/// - 30% presupuesto: 30 si el usuario declaró un monto, 0 si no.
/// - 30% datos de mercado: 30 si fetch_ok, 0 si falló la cotización.
int computeFitScore({
  required bool fetchOk,
  required bool hasBudget,
  required bool addsDiversification,
  required double? sectorOverlapPct,
}) {
  final diversificationScore = addsDiversification
      ? 40
      : (40 * (1 - ((sectorOverlapPct ?? 0) / 100))).round().clamp(0, 40);

  final budgetScore = hasBudget ? 30 : 0;
  final fetchScore = fetchOk ? 30 : 0;

  return diversificationScore + budgetScore + fetchScore;
}
