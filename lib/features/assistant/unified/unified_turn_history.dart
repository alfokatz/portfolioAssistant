import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';

/// Continuidad de tema entre turnos del pipeline unificado, resuelta de
/// forma determinística desde los mensajes ya guardados — no con una
/// variable suelta ni con una llamada extra al modelo. El contexto se arma
/// ANTES de llamar al modelo, así que el "ticker en curso" tiene que
/// conocerse acá para poder pedir sus datos (ej. las noticias de AAPL ante
/// "¿y las noticias?").
abstract final class UnifiedTurnHistory {
  /// El primer ticker del turno más reciente que resolvió alguno.
  static String? followUpTicker(List<PortfolioQaMessage> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.role != PortfolioQaRole.assistant) continue;
      if (message.subjectTickers.isNotEmpty) {
        return message.subjectTickers.first;
      }
    }
    return null;
  }
}
