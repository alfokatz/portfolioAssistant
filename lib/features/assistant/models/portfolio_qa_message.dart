import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';

/// Mensaje de la conversación Portfolio Q&A (UI).
enum PortfolioQaRole { user, assistant }

class PortfolioQaMessage {
  const PortfolioQaMessage({
    required this.role,
    this.content = '',
    this.surfaceId,
    this.isStreaming = false,
    this.engineMode,
  });

  final PortfolioQaRole role;
  final String content;
  final String? surfaceId;
  final bool isStreaming;

  final AssistantMode? engineMode;

  bool get isGenUiSurface => surfaceId != null;

  PortfolioQaMessage copyWith({
    PortfolioQaRole? role,
    String? content,
    String? surfaceId,
    bool? isStreaming,
    AssistantMode? engineMode,
  }) {
    return PortfolioQaMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      surfaceId: surfaceId ?? this.surfaceId,
      isStreaming: isStreaming ?? this.isStreaming,
      engineMode: engineMode ?? this.engineMode,
    );
  }
}
