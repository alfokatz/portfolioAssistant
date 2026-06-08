import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Segment control para alternar entre inicio de sesión y registro.
class AuthTabSwitcher extends StatelessWidget {
  const AuthTabSwitcher({
    super.key,
    required this.isSignUpMode,
    required this.onSignInTap,
    required this.onSignUpTap,
    required this.signInLabel,
    required this.signUpLabel,
    this.enabled = true,
  });

  final bool isSignUpMode;
  final VoidCallback onSignInTap;
  final VoidCallback onSignUpTap;
  final String signInLabel;
  final String signUpLabel;
  final bool enabled;

  static const _radius = 12.0;
  static const _height = 48.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: PortfolioColors.surfaceCard,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: PortfolioColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabSegment(
              label: signInLabel,
              isActive: !isSignUpMode,
              onTap: enabled ? onSignInTap : null,
            ),
          ),
          Expanded(
            child: _TabSegment(
              label: signUpLabel,
              isActive: isSignUpMode,
              onTap: enabled ? onSignUpTap : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabSegment extends StatelessWidget {
  const _TabSegment({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? PortfolioColors.accentBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: PortfolioColors.accentBlue.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: isActive
                      ? PortfolioColors.textPrimary
                      : PortfolioColors.textSecondary,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
          ),
        ),
      ),
    );
  }
}
