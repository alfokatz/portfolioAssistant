/// Mensaje de la conversación Portfolio Q&A (UI).
enum PortfolioQaRole { user, assistant }

class PortfolioQaMessage {
  const PortfolioQaMessage({
    required this.role,
    this.content = '',
    this.surfaceId,
    this.isStreaming = false,
  });

  final PortfolioQaRole role;
  final String content;
  final String? surfaceId;
  final bool isStreaming;

  bool get isGenUiSurface => surfaceId != null;

  PortfolioQaMessage copyWith({
    PortfolioQaRole? role,
    String? content,
    String? surfaceId,
    bool? isStreaming,
  }) {
    return PortfolioQaMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      surfaceId: surfaceId ?? this.surfaceId,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}
