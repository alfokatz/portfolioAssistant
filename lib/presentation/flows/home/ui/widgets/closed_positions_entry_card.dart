import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

class ClosedPositionsEntryCard extends StatelessWidget {
  const ClosedPositionsEntryCard({
    super.key,
    required this.onTap,
    this.count,
  });

  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final subtitle = count != null && count! > 0
        ? 'closed_positions_entry_subtitle'.tr(namedArgs: {'count': '$count'})
        : 'closed_positions_entry_subtitle_empty'.tr();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sp16,
      ),
      child: Material(
        color: colors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.cardPadding),
            child: Row(
              children: [
                // El mismo encabezado con ícono en círculo teñido que las
                // cards de Porty (QaCardTitle).
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.textSecondary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    color: colors.textSecondary,
                    size: AppDimens.iconMd,
                  ),
                ),
                const SizedBox(width: AppDimens.sp12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'closed_positions_entry_title'.tr(),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppDimens.sp8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: AppDimens.iconMd,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
