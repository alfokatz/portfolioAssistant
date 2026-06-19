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
        ? PortfolioColors.surfaceElevated
        : PortfolioColors.surfaceCard;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: Radius.circular(isUser ? 12 : 3),
      bottomRight: Radius.circular(isUser ? 3 : 12),
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
            border: Border.all(color: PortfolioColors.border),
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
