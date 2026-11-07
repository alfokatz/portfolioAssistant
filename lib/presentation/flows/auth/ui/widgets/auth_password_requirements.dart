import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/auth/utils/auth_validators.dart';

/// Lo que le falta a la contraseña nueva, debajo de las barras de fuerza:
/// cada requisito pasa de gris a verde al cumplirse. Así el error de
/// validación nunca es una sorpresa.
class AuthPasswordRequirements extends StatelessWidget {
  const AuthPasswordRequirements({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    final colors = context.customColors;
    final style = Theme.of(context).textTheme.labelMedium;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.sp8),
      child: Wrap(
        spacing: AppDimens.sp12,
        runSpacing: AppDimens.sp4,
        children: [
          for (final requirement in PasswordRequirement.values)
            Builder(
              builder: (context) {
                final met = requirement.isMetBy(password);
                final color = met ? colors.profit : colors.textSecondary;
                return Semantics(
                  checked: met,
                  label: requirement.labelKey.tr(),
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        child: Icon(
                          met
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          key: ValueKey(met),
                          size: AppDimens.iconSm,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: AppDimens.sp4),
                      Text(
                        requirement.labelKey.tr(),
                        style: style?.copyWith(color: color),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
