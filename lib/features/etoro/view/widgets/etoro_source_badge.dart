import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Marca discreta de origen: "eToro" en gris sobre Elevated Mist, del alto
/// de una línea de label. No usa colores de marca de eToro: es un dato, no
/// publicidad, y no compite con las cifras.
class EtoroSourceBadge extends StatelessWidget {
  const EtoroSourceBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Semantics(
      label: 'etoro_badge_semantics'.tr(),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        ),
        child: Text(
          'etoro_badge'.tr(),
          maxLines: 1,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
            height: 1.2,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}
