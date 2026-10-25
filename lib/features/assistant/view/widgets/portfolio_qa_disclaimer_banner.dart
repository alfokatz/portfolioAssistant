import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';

class PortfolioQaDisclaimerBanner extends StatelessWidget {
  const PortfolioQaDisclaimerBanner({super.key});

  @override
  Widget build(BuildContext context) {
    // Al 50% quedaba por debajo de 3:1 en ambos temas; al 80% el aviso
    // sigue siendo el texto más callado de la pantalla y se puede leer.
    final dim = context.customColors.textSecondary.withValues(alpha: 0.8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        AppDimens.sp4,
        AppDimens.pageHorizontal,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 11, color: dim),
          const SizedBox(width: AppDimens.sp4),
          Expanded(
            child: Text(
              'portfolio_qa_disclaimer'.tr(),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: dim, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
