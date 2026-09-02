import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/routing/intent_router.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';

class AssistantArgs {
  const AssistantArgs({
    this.initialMode = AssistantMode.portfolio,
    this.initialQuestion,
  });

  final AssistantMode initialMode;
  final String? initialQuestion;
}

/// Estado del asistente. Cada [AssistantMode] (pestaña) mantiene su propia
/// conversación: mensajes, error y último mensaje enviado quedan aislados
/// por modo, así cambiar de pestaña no mezcla ni pierde el hilo de otra.
class AssistantState {
  final Map<AssistantMode, List<PortfolioQaMessage>> messagesByMode;
  final Map<AssistantMode, String?> errorByMode;
  final Map<AssistantMode, String> lastMessageByMode;
  final bool isWaiting;
  final bool bootstrapped;
  final int turnCounter;
  final AssistantMode currentMode;
  final ModeSuggestion? modeSuggestion;
  final String? pendingMessage;
  final bool isServiceReady;
  final PaywallReason? paywallReason;

  const AssistantState({
    this.messagesByMode = const {},
    this.errorByMode = const {},
    this.lastMessageByMode = const {},
    this.isWaiting = false,
    this.bootstrapped = false,
    this.turnCounter = 0,
    this.currentMode = AssistantMode.portfolio,
    this.modeSuggestion,
    this.pendingMessage,
    this.isServiceReady = false,
    this.paywallReason,
  });

  List<PortfolioQaMessage> get messages =>
      messagesByMode[currentMode] ?? const [];

  String? get error => errorByMode[currentMode];

  String get lastMessage => lastMessageByMode[currentMode] ?? '';

  AssistantState copyWith({
    Map<AssistantMode, List<PortfolioQaMessage>>? messagesByMode,
    Map<AssistantMode, String?>? errorByMode,
    Map<AssistantMode, String>? lastMessageByMode,
    bool? isWaiting,
    bool? bootstrapped,
    int? turnCounter,
    AssistantMode? currentMode,
    ModeSuggestion? modeSuggestion,
    String? pendingMessage,
    bool? isServiceReady,
    PaywallReason? paywallReason,
    bool clearModeSuggestion = false,
    bool clearPendingMessage = false,
    bool clearPaywallReason = false,
  }) {
    return AssistantState(
      messagesByMode: messagesByMode ?? this.messagesByMode,
      errorByMode: errorByMode ?? this.errorByMode,
      lastMessageByMode: lastMessageByMode ?? this.lastMessageByMode,
      isWaiting: isWaiting ?? this.isWaiting,
      bootstrapped: bootstrapped ?? this.bootstrapped,
      turnCounter: turnCounter ?? this.turnCounter,
      currentMode: currentMode ?? this.currentMode,
      modeSuggestion:
          clearModeSuggestion ? null : (modeSuggestion ?? this.modeSuggestion),
      pendingMessage:
          clearPendingMessage ? null : (pendingMessage ?? this.pendingMessage),
      isServiceReady: isServiceReady ?? this.isServiceReady,
      paywallReason:
          clearPaywallReason ? null : (paywallReason ?? this.paywallReason),
    );
  }
}
