import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Contenedor suave que agrupa el formulario de autenticación.
class AuthFormCard extends StatelessWidget {
  const AuthFormCard({super.key, required this.child});

  final Widget child;

  static const _radius = 24.0;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PortfolioColors.surfaceCard.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(
          color: PortfolioColors.border.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: child,
      ),
    );
  }
}
