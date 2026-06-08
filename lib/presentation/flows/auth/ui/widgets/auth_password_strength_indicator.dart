import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/flows/auth/utils/password_strength.dart';

/// Barras de fortaleza de contraseña con etiqueta (DÉBIL / MEDIA / FUERTE).
class AuthPasswordStrengthIndicator extends StatelessWidget {
  const AuthPasswordStrengthIndicator({super.key, required this.password});

  final String password;

  static const _barCount = 4;

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) {
      return const SizedBox(height: 8);
    }

    final score = PasswordStrengthEvaluator.score(password);
    final level = PasswordStrengthEvaluator.level(password);
    final activeColor = switch (level) {
      PasswordStrength.weak => PortfolioColors.loss,
      PasswordStrength.medium => const Color(0xFFF59E0B),
      PasswordStrength.strong => PortfolioColors.profit,
    };
    final label = switch (level) {
      PasswordStrength.weak => 'auth_password_strength_weak'.tr(),
      PasswordStrength.medium => 'auth_password_strength_medium'.tr(),
      PasswordStrength.strong => 'auth_password_strength_strong'.tr(),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: List.generate(_barCount, (index) {
              final isActive = index < score;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index < _barCount - 1 ? 6 : 0,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 4,
                    decoration: BoxDecoration(
                      color: isActive ? activeColor : PortfolioColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: activeColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
