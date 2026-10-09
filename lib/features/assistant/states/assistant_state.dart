import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';

class AssistantArgs {
  const AssistantArgs({this.initialQuestion});

  final String? initialQuestion;
}

/// Una pregunta para Porty que llega desde fuera del chat (chips de Home,
/// detalle de una posición, informe semanal). Es un objeto nuevo en cada
/// toque a propósito, sin `==` por valor: la pestaña de Porty queda montada
/// en el shell, así que la pantalla se entera por `didUpdateWidget` y tiene
/// que distinguir un toque nuevo aunque repita la misma pregunta.
class AssistantQuestionRequest {
  AssistantQuestionRequest(this.question);

  final String question;
}

/// Estado del asistente: un único hilo de conversación con Porty.
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

  /// En qué quedó cada operación que propuso Porty, por `proposal_id`. Una
  /// propuesta que no está acá sigue pendiente (ver [actionProgress]).
  final Map<String, ActionProposalProgress> actionProposals;

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
    this.actionProposals = const {},
  });

  ActionProposalProgress actionProgress(String proposalId) =>
      actionProposals[proposalId] ?? ActionProposalProgress.pending;

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
    Map<String, ActionProposalProgress>? actionProposals,
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
      actionProposals: actionProposals ?? this.actionProposals,
    );
  }
}
