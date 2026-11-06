import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_prompt_provider.dart';
import 'package:portfolio_assistant/features/home_widget/view/widget_add_sheet.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_nav_row.dart';

/// Ajustes: "Widget de Porty". Abre la misma hoja que la oferta; si ya hay
/// uno instalado, lo dice y la hoja va directo a los pasos para sumar otro
/// tamaño.
class WidgetAddTile extends ConsumerWidget {
  const WidgetAddTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed =
        ref.watch(widgetInstalledSizesProvider).valueOrNull?.isNotEmpty ??
        false;
    return SettingsNavRow(
      icon: Icons.widgets_outlined,
      label: 'home_widget_add_row'.tr(),
      subtitle:
          installed
              ? 'home_widget_add_row_installed'.tr()
              : 'home_widget_add_row_idle'.tr(),
      onTap: () async {
        await WidgetAddSheet.show(
          context,
          ref,
          source: WidgetPromptSource.settings,
          installed: installed,
        );
        // Pudo haberlo agregado desde la hoja.
        ref.invalidate(widgetInstalledSizesProvider);
      },
    );
  }
}
