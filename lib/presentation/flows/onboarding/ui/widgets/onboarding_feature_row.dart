import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Una función de la app: ícono en un círculo teñido (como los
/// encabezados de las cards), título y una línea. Con [tag], el plan que la
/// incluye ("Premium", "Gold"), para no prometer de más.
class OnboardingFeatureRow extends StatelessWidget {
  const OnboardingFeatureRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.tag,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.accentBlue.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: colors.accentBlue, size: AppDimens.iconMd),
        ),
        const SizedBox(width: AppDimens.sp12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppDimens.sp8,
                runSpacing: AppDimens.sp4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    title,
                    style: tt.titleSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  if (tag != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.sp6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.accentBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
                      ),
                      child: Text(
                        tag!,
                        style: tt.labelSmall?.copyWith(
                          color: colors.accentBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppDimens.sp2),
              Text(
                subtitle,
                style: tt.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
