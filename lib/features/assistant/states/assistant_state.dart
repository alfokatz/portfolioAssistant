import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';

class AssistantArgs {
  const AssistantArgs({
    this.initialMode = AssistantMode.portfolio,
    this.initialQuestion,
  });

  final AssistantMode initialMode;
  final String? initialQuestion;
}

/// Estado del asistente: un único hilo de conversación. Puertas adentro cada
/// mensaje puede resolverse con un motor distinto (portfolio/learn/explore/
/// invest/plan), pero de cara al usuario es un solo chat continuo.
class AssistantState {
  final List<PortfolioQaMessage> messages;
  final String? error;
  final String lastMessage;
  final bool isWaiting;
  final bool bootstrapped;
  final int turnCounter;
  final bool isServiceReady;
  final PaywallReason? paywallReason;

  /// `true` una vez que la cascada de entrada del saludo inicial + chips de
  /// sugerencia (ver `FadeSlideIn` en `AssistantScreen`) ya se mostró al
  /// menos una vez. Vive acá (no en el `State` de ningún widget) por la
  /// misma razón que `PortfolioQaMessage.hasRevealed`: esos widgets son
  /// items del `ListView` del chat, que los desmonta si scrollean fuera del
  /// cache extent — sin este flag persistente, volver a scrollear hasta
  /// arriba del todo reproduce la cascada de nuevo.
  final bool introRevealed;

  const AssistantState({
    this.messages = const [],
    this.error,
    this.lastMessage = '',
    this.isWaiting = false,
    this.bootstrapped = false,
    this.turnCounter = 0,
    this.isServiceReady = false,
    this.paywallReason,
    this.introRevealed = false,
  });

  AssistantState copyWith({
    List<PortfolioQaMessage>? messages,
    String? error,
    String? lastMessage,
    bool? isWaiting,
    bool? bootstrapped,
    int? turnCounter,
    bool? isServiceReady,
    PaywallReason? paywallReason,
    bool? introRevealed,
    bool clearError = false,
    bool clearPaywallReason = false,
  }) {
    return AssistantState(
      messages: messages ?? this.messages,
      error: clearError ? null : (error ?? this.error),
      lastMessage: lastMessage ?? this.lastMessage,
      isWaiting: isWaiting ?? this.isWaiting,
      bootstrapped: bootstrapped ?? this.bootstrapped,
      turnCounter: turnCounter ?? this.turnCounter,
      isServiceReady: isServiceReady ?? this.isServiceReady,
      paywallReason:
          clearPaywallReason ? null : (paywallReason ?? this.paywallReason),
      introRevealed: introRevealed ?? this.introRevealed,
    );
  }
}
