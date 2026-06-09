import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Encabezado acogedor con marca, saludo contextual y tagline.
class AuthWelcomeHeader extends StatelessWidget {
  const AuthWelcomeHeader({super.key, required this.isSignUpMode});

  final bool isSignUpMode;

  static const _warmAccent = Color(0xFFFBBF24);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = isSignUpMode
        ? 'auth_subtitle_sign_up'.tr()
        : 'auth_subtitle_sign_in'.tr();

    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                PortfolioColors.accentBlue.withValues(alpha: 0.9),
                PortfolioColors.accentBlueDim,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: PortfolioColors.accentBlue.withValues(alpha: 0.3),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: _warmAccent.withValues(alpha: 0.15),
                blurRadius: 32,
                spreadRadius: -4,
              ),
            ],
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: PortfolioColors.textPrimary,
            size: 34,
          ),
        ),
        const SizedBox(height: AppDimens.mediumMargin),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Portfolio',
                style: theme.textTheme.displayLarge?.copyWith(
                  color: PortfolioColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              TextSpan(
                text: 'AI',
                style: theme.textTheme.displayLarge?.copyWith(
                  color: PortfolioColors.accentBlue,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppDimens.smallMargin),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: PortfolioColors.textPrimary.withValues(alpha: 0.85),
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'auth_tagline'.tr(),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: PortfolioColors.textSecondary,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
