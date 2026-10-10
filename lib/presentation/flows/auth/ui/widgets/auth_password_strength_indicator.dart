import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_gold_theme.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/auth/utils/password_strength.dart';

/// Barras de fortaleza de contraseña con etiqueta.
class AuthPasswordStrengthIndicator extends StatelessWidget {
  const AuthPasswordStrengthIndicator({super.key, required this.password});

  final String password;

  static const _barCount = 4;

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) {
      return const SizedBox(height: AppDimens.sp8);
    }

    final colors = context.customColors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 200);

    final score = PasswordStrengthEvaluator.score(password);
    final level = PasswordStrengthEvaluator.level(password);
    final activeColor = switch (level) {
      PasswordStrength.weak => colors.loss,
      PasswordStrength.medium => SubscriptionGoldTheme.accent,
      PasswordStrength.strong => colors.profit,
    };
    final label = switch (level) {
      PasswordStrength.weak => 'auth_password_strength_weak'.tr(),
      PasswordStrength.medium => 'auth_password_strength_medium'.tr(),
      PasswordStrength.strong => 'auth_password_strength_strong'.tr(),
    };

    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.sp8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: List.generate(_barCount, (index) {
              final isActive = index < score;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index < _barCount - 1 ? AppDimens.sp6 : 0,
                  ),
                  child: AnimatedContainer(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isActive ? activeColor : colors.border,
                      borderRadius: BorderRadius.circular(AppDimens.sp2),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: AppDimens.sp6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: activeColor,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
