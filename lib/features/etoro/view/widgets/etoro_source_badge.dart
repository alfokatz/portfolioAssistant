import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_images.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Marca de origen: el logo de eToro en su verde sobre Elevated Mist, del
/// alto de una línea de label. Va al lado del ticker, lejos de las cifras:
/// su verde (más brillante) no se confunde con el de la ganancia.
class EtoroSourceBadge extends StatelessWidget {
  const EtoroSourceBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Semantics(
      label: 'etoro_badge_semantics'.tr(),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        ),
        child: AppImages.etoroLogo(height: 8),
      ),
    );
  }
}
