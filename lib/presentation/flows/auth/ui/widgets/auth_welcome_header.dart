import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

class AuthWelcomeHeader extends StatelessWidget {
  const AuthWelcomeHeader({super.key, required this.isSignUpMode});

  final bool isSignUpMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = isSignUpMode
        ? 'auth_subtitle_sign_up'.tr()
        : 'auth_subtitle_sign_in'.tr();

    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: PortfolioColors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            border: Border.all(color: PortfolioColors.border),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: PortfolioColors.accentBlue,
            size: AppDimens.iconLg,
          ),
        ),
        const SizedBox(height: AppDimens.sp20),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Portfolio',
                style: theme.textTheme.displaySmall?.copyWith(
                  color: PortfolioColors.textPrimary,
                ),
              ),
              TextSpan(
                text: 'AI',
                style: theme.textTheme.displaySmall?.copyWith(
                  color: PortfolioColors.accentBlue,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppDimens.sp8),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: PortfolioColors.textPrimary.withValues(alpha: 0.8),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppDimens.sp4),
        Text(
          'auth_tagline'.tr(),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: PortfolioColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
