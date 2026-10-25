import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_mode_provider.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_picker_sheet.dart';

Future<void> showSettingsAppearancePicker(BuildContext context, WidgetRef ref) {
  final current = ref.read(themeModeProvider);

  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SettingsPickerSheet(
      title: 'settings_appearance'.tr(),
      children: [
        SettingsPickerOption(
          label: 'settings_appearance_system'.tr(),
          icon: Icons.brightness_auto_rounded,
          isSelected: current == ThemeMode.system,
          onTap: () => _select(ctx, ref, ThemeMode.system),
        ),
        SettingsPickerOption(
          label: 'settings_appearance_light'.tr(),
          icon: Icons.light_mode_outlined,
          isSelected: current == ThemeMode.light,
          onTap: () => _select(ctx, ref, ThemeMode.light),
        ),
        SettingsPickerOption(
          label: 'settings_appearance_dark'.tr(),
          icon: Icons.dark_mode_outlined,
          isSelected: current == ThemeMode.dark,
          onTap: () => _select(ctx, ref, ThemeMode.dark),
        ),
      ],
    ),
  );
}

Future<void> _select(
  BuildContext context,
  WidgetRef ref,
  ThemeMode mode,
) async {
  await ref.read(themeModeProvider.notifier).setThemeMode(mode);
  if (context.mounted) {
    Navigator.of(context).pop();
  }
}

String settingsAppearanceLabel(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => 'settings_appearance_system'.tr(),
    ThemeMode.light => 'settings_appearance_light'.tr(),
    ThemeMode.dark => 'settings_appearance_dark'.tr(),
  };
}
