import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Separador con texto centrado para la sección de OAuth.
class AuthOauthDivider extends StatelessWidget {
  const AuthOauthDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Divider(
            color: PortfolioColors.border,
            thickness: 1,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PortfolioColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
        const Expanded(
          child: Divider(
            color: PortfolioColors.border,
            thickness: 1,
          ),
        ),
      ],
    );
  }
}
