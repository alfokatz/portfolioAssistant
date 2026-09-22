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

  const AssistantState({
    this.messages = const [],
    this.error,
    this.lastMessage = '',
    this.isWaiting = false,
    this.bootstrapped = false,
    this.turnCounter = 0,
    this.isServiceReady = false,
    this.paywallReason,
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
    );
  }
}
