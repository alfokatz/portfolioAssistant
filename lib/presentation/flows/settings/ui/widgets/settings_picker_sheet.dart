import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

class SettingsPickerOption extends StatelessWidget {
  const SettingsPickerOption({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return ListTile(
      leading: icon == null
          ? null
          : Icon(
              icon,
              color: isSelected ? colors.accentBlue : colors.textSecondary,
            ),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_rounded, color: colors.accentBlue)
          : null,
      onTap: onTap,
    );
  }
}

class SettingsPickerSheet extends StatelessWidget {
  const SettingsPickerSheet({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          ...children,
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
