/// IDs de surface GenUI por flujo.
abstract final class GenUiSurfaceIds {
  static const portfolioAnalysis = 'portfolio_analysis';
  static const investmentDecision = 'investment_decision';
  static const longTermPlanning = 'long_term_planning';
  static const portfolioQaPrefix = 'portfolio_qa';

  static String portfolioQaTurn(int turnIndex) =>
      '${portfolioQaPrefix}_$turnIndex';

  static const assistantPrefix = 'assistant_';

  /// Surface de la respuesta a un turno del asistente.
  static String assistantTurn(int turn) => '$assistantPrefix$turn';
}
