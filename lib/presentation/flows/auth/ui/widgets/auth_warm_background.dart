import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Fondo para pantallas de auth: base oscura con un único halo de acento sutil.
class AuthWarmBackground extends StatelessWidget {
  const AuthWarmBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Halo único en indigo — da profundidad sin ruido cromático
        Positioned(
          top: -120,
          right: -100,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  PortfolioColors.accentBlue.withValues(alpha: 0.07),
                  PortfolioColors.accentBlue.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
