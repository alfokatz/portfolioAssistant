import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Entrada principal al asistente de preguntas sobre el portfolio.
class PortfolioQaEntryCard extends StatelessWidget {
  const PortfolioQaEntryCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Material(
        color: PortfolioColors.accentBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: PortfolioColors.accentBlue.withValues(alpha: 0.55),
                width: 1.2,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: PortfolioColors.accentBlue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline,
                    color: PortfolioColors.accentBlue,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'portfolio_qa_entry_title'.tr(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: PortfolioColors.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'portfolio_qa_entry_subtitle'.tr(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: PortfolioColors.textSecondary,
                              height: 1.3,
                            ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: PortfolioColors.accentBlue,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
