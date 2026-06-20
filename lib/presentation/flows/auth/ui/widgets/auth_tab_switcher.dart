import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

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

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FlatTab(
          label: signInLabel,
          isActive: !isSignUpMode,
          onTap: enabled ? onSignInTap : null,
        ),
        const SizedBox(width: 24),
        _FlatTab(
          label: signUpLabel,
          isActive: isSignUpMode,
          onTap: enabled ? onSignUpTap : null,
        ),
      ],
    );
  }
}

class _FlatTab extends StatelessWidget {
  const _FlatTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall?.copyWith(
      color: isActive ? PortfolioColors.textPrimary : PortfolioColors.textSecondary,
      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(label, style: style),
          const SizedBox(height: 5),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: 2,
            color: isActive ? PortfolioColors.textPrimary : Colors.transparent,
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
