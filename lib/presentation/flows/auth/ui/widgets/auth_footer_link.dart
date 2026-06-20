import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Enlace de pie con texto secundario y acción destacada.
class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({
    super.key,
    required this.prefix,
    required this.actionLabel,
    required this.onActionTap,
    this.enabled = true,
  });

  final String prefix;
  final String actionLabel;
  final VoidCallback onActionTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final baseStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: colors.textSecondary,
        );
    final actionStyle = baseStyle?.copyWith(
      color: enabled
          ? colors.accentBlue
          : colors.accentBlue.withValues(alpha: 0.5),
      fontWeight: FontWeight.w700,
    );

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: actionLabel,
            style: actionStyle,
            recognizer: enabled
                ? (TapGestureRecognizer()..onTap = onActionTap)
                : null,
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
