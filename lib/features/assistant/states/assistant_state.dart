import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/routing/intent_router.dart';

class AssistantArgs {
  const AssistantArgs({
    this.initialMode = AssistantMode.portfolio,
    this.initialQuestion,
  });

  final AssistantMode initialMode;
  final String? initialQuestion;
}

class AssistantState {
  final List<PortfolioQaMessage> messages;
  final String? error;
  final bool isWaiting;
  final bool bootstrapped;
  final int turnCounter;
  final String lastMessage;
  final AssistantMode currentMode;
  final ModeSuggestion? modeSuggestion;
  final String? pendingMessage;
  final bool isServiceReady;

  const AssistantState({
    this.messages = const [],
    this.error,
    this.isWaiting = false,
    this.bootstrapped = false,
    this.turnCounter = 0,
    this.lastMessage = '',
    this.currentMode = AssistantMode.portfolio,
    this.modeSuggestion,
    this.pendingMessage,
    this.isServiceReady = false,
  });

  AssistantState copyWith({
    List<PortfolioQaMessage>? messages,
    String? error,
    bool? isWaiting,
    bool? bootstrapped,
    int? turnCounter,
    String? lastMessage,
    AssistantMode? currentMode,
    ModeSuggestion? modeSuggestion,
    String? pendingMessage,
    bool? isServiceReady,
    bool clearError = false,
    bool clearModeSuggestion = false,
    bool clearPendingMessage = false,
  }) {
    return AssistantState(
      messages: messages ?? this.messages,
      error: clearError ? null : (error ?? this.error),
      isWaiting: isWaiting ?? this.isWaiting,
      bootstrapped: bootstrapped ?? this.bootstrapped,
      turnCounter: turnCounter ?? this.turnCounter,
      lastMessage: lastMessage ?? this.lastMessage,
      currentMode: currentMode ?? this.currentMode,
      modeSuggestion:
          clearModeSuggestion ? null : (modeSuggestion ?? this.modeSuggestion),
      pendingMessage:
          clearPendingMessage ? null : (pendingMessage ?? this.pendingMessage),
      isServiceReady: isServiceReady ?? this.isServiceReady,
    );
  }
}
