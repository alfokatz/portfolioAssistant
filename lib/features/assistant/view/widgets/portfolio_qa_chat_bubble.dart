import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_thinking_orb.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
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
      topLeft: const Radius.circular(AppDimens.radiusLg),
      topRight: const Radius.circular(AppDimens.radiusLg),
      bottomLeft: Radius.circular(isUser ? AppDimens.radiusLg : 4),
      bottomRight: Radius.circular(isUser ? 4 : AppDimens.radiusLg),
    );

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppDimens.sp12),
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: AppDimens.sp12,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius,
            // User bubbles: no border — surface lift is sufficient distinction.
            // AI bubbles: border marks received content.
            border: isUser ? null : Border.all(color: PortfolioColors.border),
          ),
          child: message.isStreaming && message.content.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: AssistantThinkingOrb(size: 18),
                )
              : SelectableText(
                  message.content,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: PortfolioColors.textPrimary,
                        height: 1.5,
                      ),
                ),
        ),
      ),
    );
  }
}
