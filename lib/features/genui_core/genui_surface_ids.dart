import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';

/// IDs de surface GenUI por flujo.
abstract final class GenUiSurfaceIds {
  static const portfolioAnalysis = 'portfolio_analysis';
  static const investmentDecision = 'investment_decision';
  static const longTermPlanning = 'long_term_planning';
  static const portfolioQaPrefix = 'portfolio_qa';

  static String portfolioQaTurn(int turnIndex) => '${portfolioQaPrefix}_$turnIndex';

  static String assistantTurn(AssistantMode mode, int turn) =>
      'assistant_${mode.name}_$turn';
}
