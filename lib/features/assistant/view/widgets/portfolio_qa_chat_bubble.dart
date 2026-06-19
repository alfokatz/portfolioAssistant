import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

class PortfolioQaChatBubble extends StatelessWidget {
  const PortfolioQaChatBubble({
    super.key,
    required this.message,
  });

  final PortfolioQaMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == PortfolioQaRole.user;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bg = isUser
        ? PortfolioColors.accentBlue.withValues(alpha: 0.25)
        : PortfolioColors.surfaceCard;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft: Radius.circular(isUser ? 14 : 4),
      bottomRight: Radius.circular(isUser ? 4 : 14),
    );

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius,
            border: isUser
                ? null
                : Border.all(
                    color: PortfolioColors.textSecondary.withValues(alpha: 0.2),
                  ),
          ),
          child: message.isStreaming && message.content.isEmpty
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: PortfolioColors.accentBlue,
                  ),
                )
              : SelectableText(
                  message.content,
                  style: const TextStyle(
                    color: PortfolioColors.textPrimary,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
        ),
      ),
    );
  }
}
