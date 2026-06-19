import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

class SettingsDangerZone extends StatelessWidget {
  const SettingsDangerZone({
    super.key,
    required this.onSignOut,
    required this.onDeleteAccount,
  });

  final VoidCallback onSignOut;
  final VoidCallback onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'settings_danger_zone'.tr(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: PortfolioColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                ),
          ),
        ),
        _DangerButton(
          label: 'auth_sign_out'.tr(),
          color: PortfolioColors.accentBlue,
          onTap: onSignOut,
        ),
        const SizedBox(height: 10),
        _DangerButton(
          label: 'settings_delete_account'.tr(),
          color: const Color(0xFFF97316),
          onTap: onDeleteAccount,
        ),
      ],
    );
  }
}

class _DangerButton extends StatelessWidget {
  const _DangerButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PortfolioColors.surfaceCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: PortfolioColors.border),
          ),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
