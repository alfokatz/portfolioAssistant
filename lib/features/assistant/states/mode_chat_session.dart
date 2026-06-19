import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';

/// Historial de chat persistido en memoria para un modo del asistente.
class ModeChatSession {
  const ModeChatSession({
    required this.messages,
    this.turnCounter = 0,
    this.lastMessage = '',
  });

  final List<PortfolioQaMessage> messages;
  final int turnCounter;
  final String lastMessage;

  ModeChatSession copyWith({
    List<PortfolioQaMessage>? messages,
    int? turnCounter,
    String? lastMessage,
  }) {
    return ModeChatSession(
      messages: messages ?? this.messages,
      turnCounter: turnCounter ?? this.turnCounter,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }

  /// Quita placeholders de streaming incompletos antes de persistir.
  static List<PortfolioQaMessage> sanitizeMessages(
    List<PortfolioQaMessage> messages,
  ) {
    if (messages.isEmpty) return messages;
    final last = messages.last;
    if (last.isStreaming) {
      return messages.sublist(0, messages.length - 1);
    }
    return [...messages];
  }
}
