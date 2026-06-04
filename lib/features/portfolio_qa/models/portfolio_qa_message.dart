/// Mensaje de la conversación Portfolio Q&A (UI).
enum PortfolioQaRole { user, assistant }

class PortfolioQaMessage {
  const PortfolioQaMessage({
    required this.role,
    required this.content,
    this.isStreaming = false,
  });

  final PortfolioQaRole role;
  final String content;
  final bool isStreaming;

  PortfolioQaMessage copyWith({
    PortfolioQaRole? role,
    String? content,
    bool? isStreaming,
  }) {
    return PortfolioQaMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}
