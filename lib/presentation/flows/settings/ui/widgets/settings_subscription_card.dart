import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

class SettingsSubscriptionCard extends StatelessWidget {
  const SettingsSubscriptionCard({
    super.key,
    required this.onUpgradeTap,
  });

  final VoidCallback onUpgradeTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PortfolioColors.surfaceCard,
            PortfolioColors.surfaceElevated.withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PortfolioColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: PortfolioColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: PortfolioColors.border),
                ),
                child: Text(
                  'settings_plan_free'.tr(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: PortfolioColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.auto_awesome,
                color: PortfolioColors.accentBlue,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'settings_pro_description'.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: PortfolioColors.textPrimary,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF2563EB),
                    Color(0xFF06B6D4),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onUpgradeTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text(
                        'settings_upgrade_pro'.tr(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: PortfolioColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
