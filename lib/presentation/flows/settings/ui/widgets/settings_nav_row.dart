import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

class SettingsNavRow extends StatelessWidget {
  const SettingsNavRow({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _SettingsIconBox(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: PortfolioColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
              if (value != null) ...[
                Text(
                  value!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: PortfolioColors.textSecondary,
                      ),
                ),
                const SizedBox(width: 4),
              ],
              if (showChevron && onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: PortfolioColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          _SettingsIconBox(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: PortfolioColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: PortfolioColors.accentBlue,
            activeThumbColor: PortfolioColors.textPrimary,
          ),
        ],
      ),
    );
  }
}

class _SettingsIconBox extends StatelessWidget {
  const _SettingsIconBox({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: PortfolioColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: PortfolioColors.border.withValues(alpha: 0.5),
        ),
      ),
      child: Icon(
        icon,
        size: 18,
        color: PortfolioColors.accentBlue,
      ),
    );
  }
}
