import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Marca de origen "Bróker" (importada de un bróker conectado por
/// SnapTrade): texto sobre el fondo elevado, como la de eToro y Binance.
class SnaptradeSourceBadge extends StatelessWidget {
  const SnaptradeSourceBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Semantics(
      label: 'snaptrade_badge_semantics'.tr(),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        ),
        child: Text(
          'snaptrade_badge'.tr(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 9,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
