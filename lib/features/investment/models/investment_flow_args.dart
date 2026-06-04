/// Argumentos de navegación al flujo de decisión de inversión.
class InvestmentFlowArgs {
  final String? initialPrompt;
  final String? suggestedTicker;

  const InvestmentFlowArgs({
    this.initialPrompt,
    this.suggestedTicker,
  });

  String resolveInitialPrompt() {
    if (initialPrompt != null && initialPrompt!.trim().isNotEmpty) {
      return initialPrompt!.trim();
    }
    if (suggestedTicker != null && suggestedTicker!.trim().isNotEmpty) {
      return 'Quiero evaluar una inversión en ${suggestedTicker!.trim().toUpperCase()}. ¿Qué me recomendás?';
    }
    return 'Quiero hacer una nueva inversión. ¿Qué me recomendás?';
  }
}
