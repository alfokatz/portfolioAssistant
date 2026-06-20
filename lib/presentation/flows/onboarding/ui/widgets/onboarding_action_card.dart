import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

class OnboardingActionCard extends StatelessWidget {
  const OnboardingActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isPrimary = false,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return Semantics(
      button: true,
      enabled: enabled,
      label: title,
      hint: subtitle,
      child: Material(
        color: isPrimary ? colors.surfaceElevated : colors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          side: BorderSide(
            color: isPrimary ? colors.textPrimary : colors.border,
            width: isPrimary ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.sp16),
            child: Row(
              children: [
                Container(
                  width: AppDimens.touchTarget,
                  height: AppDimens.touchTarget,
                  decoration: BoxDecoration(
                    color:
                        isPrimary ? colors.surfaceCard : colors.surfaceElevated,
                    borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                    border: Border.all(color: colors.border),
                  ),
                  child: Icon(
                    icon,
                    color: isPrimary ? colors.textPrimary : colors.accentBlue,
                  ),
                ),
              const SizedBox(width: AppDimens.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppDimens.sp4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
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
