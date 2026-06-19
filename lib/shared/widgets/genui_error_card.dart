import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Card de fallback cuando un widgetBuilder de GenUI falla al renderizar.
class GenUiErrorCard extends StatelessWidget {
  const GenUiErrorCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PortfolioColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: PortfolioColors.loss.withValues(alpha: 0.3),
        ),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: PortfolioColors.loss,
            size: 20,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'No se pudo renderizar este componente.',
              style: TextStyle(
                color: PortfolioColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
