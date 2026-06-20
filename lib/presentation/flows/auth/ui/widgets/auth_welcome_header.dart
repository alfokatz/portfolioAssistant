import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

class AuthWelcomeHeader extends StatelessWidget {
  const AuthWelcomeHeader({super.key, required this.isSignUpMode});

  final bool isSignUpMode;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final headline = isSignUpMode
        ? 'auth_headline_signup'.tr()
        : 'auth_headline_signin'.tr();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wordmark — pequeño, anchored al top
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: PortfolioColors.textPrimary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.show_chart_rounded,
                color: PortfolioColors.background,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'app_name'.tr(),
              style: tt.labelLarge?.copyWith(
                color: PortfolioColors.textPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 36),
        // Headline editorial — el elemento que más pesa visualmente
        Text(
          headline,
          style: tt.displayMedium?.copyWith(
            color: PortfolioColors.textPrimary,
            fontSize: 40,
            height: 1.05,
            letterSpacing: -1.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'auth_subheadline'.tr(),
          style: tt.bodyLarge?.copyWith(
            color: PortfolioColors.textSecondary,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}
