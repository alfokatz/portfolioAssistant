import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

class AuthWelcomeHeader extends StatelessWidget {
  const AuthWelcomeHeader({super.key, required this.isSignUpMode});

  final bool isSignUpMode;

  static const _wordmarkBadgeSize = 32.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final headline = isSignUpMode
        ? 'auth_headline_signup'.tr()
        : 'auth_headline_signin'.tr();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: _wordmarkBadgeSize,
              height: _wordmarkBadgeSize,
              decoration: BoxDecoration(
                color: colors.textPrimary,
                borderRadius: BorderRadius.circular(AppDimens.sp8),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: colors.background,
                size: AppDimens.iconMd,
              ),
            ),
            const SizedBox(width: AppDimens.sp12),
            Text(
              'app_name'.tr(),
              style: tt.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.sp32),
        Text(
          headline,
          style: tt.displayMedium?.copyWith(
            color: colors.textPrimary,
            fontSize: 40,
            height: 1.05,
            letterSpacing: -1.5,
          ),
        ),
        const SizedBox(height: AppDimens.sp8),
        Text(
          'auth_subheadline'.tr(),
          style: tt.bodyLarge?.copyWith(
            color: colors.textSecondary,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}
