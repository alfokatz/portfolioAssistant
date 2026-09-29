/// Calcula fit_score (0–100) para un candidato de inversión simulada: qué
/// tan bien encaja ESE ticker con el portfolio y el perfil del usuario.
///
/// Fórmula:
/// - 50% diversificación: 50 si el sector del candidato difiere del sector
///   sobrepeso del portfolio; si coincide, 50 × (1 − pesoSector/100).
/// - 35% perfil: 35 si el nivel de riesgo encaja con la tolerancia del
///   perfil, 0 si no encaja, 20 (neutro) sin perfil o sin beta — no premiar
///   ni castigar lo que no se sabe.
/// - 15% datos de mercado: 15 si fetch_ok, 0 si falló la cotización.
///
/// Antes sumaba 30 puntos por "el usuario dijo un presupuesto", lo que no
/// dice nada del ticker: el mismo JPM daba 70 sin monto y 100 con monto, y
/// la UI mostraba un número sin sentido.
int computeFitScore({
  required bool fetchOk,
  required bool addsDiversification,
  required double? sectorOverlapPct,
  bool? matchesProfile,
}) {
  final diversificationScore =
      addsDiversification
          ? 50
          : (50 * (1 - ((sectorOverlapPct ?? 0) / 100))).round().clamp(0, 50);

  final profileScore = switch (matchesProfile) {
    true => 35,
    false => 0,
    null => 20,
  };
  final fetchScore = fetchOk ? 15 : 0;

  return diversificationScore + profileScore + fetchScore;
}

/// Lectura humana del fit_score, compartida por el widget y los tests para
/// que "Buen encaje" signifique lo mismo en todos lados.
enum FitTier {
  good('Buen encaje'),
  medium('Encaje medio'),
  low('Bajo encaje');

  const FitTier(this.label);
  final String label;

  static FitTier of(num score) {
    if (score >= 75) return FitTier.good;
    if (score >= 50) return FitTier.medium;
    return FitTier.low;
  }
}
