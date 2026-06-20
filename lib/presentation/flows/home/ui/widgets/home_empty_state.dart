import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

class HomeEmptyState extends StatelessWidget {
  const HomeEmptyState({super.key, required this.onAddPosition});

  final VoidCallback onAddPosition;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        AppDimens.sp48,
        AppDimens.pageHorizontal,
        AppDimens.sp48,
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.surfaceElevated,
              borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            ),
            child: Icon(
              Icons.pie_chart_outline_rounded,
              size: 28,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDimens.sp20),
          Text(
            'positions_empty'.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colors.textSecondary,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: AppDimens.sp24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: onAddPosition,
              style: FilledButton.styleFrom(
                backgroundColor: colors.textPrimary,
                foregroundColor: colors.surfaceCard,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                ),
              ),
              child: Text(
                'add_position'.tr(),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.surfaceCard,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
