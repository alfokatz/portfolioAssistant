import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Título grande (como los de las pantallas de la app) y una línea que lo
/// explica.
class OnboardingPageHeader extends StatelessWidget {
  const OnboardingPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.textAlign = TextAlign.start,
  });

  final String title;
  final String subtitle;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final center = textAlign == TextAlign.center;
    return Column(
      crossAxisAlignment:
          center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: textAlign,
            style: tt.displaySmall?.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.7,
              height: 1.15,
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: AppDimens.sp8),
        Text(
          subtitle,
          textAlign: textAlign,
          style: tt.bodyLarge?.copyWith(
            color: colors.textSecondary,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}
