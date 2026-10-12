import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Card de fallback cuando un widgetBuilder de GenUI falla al renderizar.
class GenUiErrorCard extends StatelessWidget {
  const GenUiErrorCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.loss.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: colors.loss,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No se pudo renderizar este componente.',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
