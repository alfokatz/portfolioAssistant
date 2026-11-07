import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_settings_provider.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_nav_row.dart';

/// Ajustes: "Ocultar posiciones en el widget", con el texto de privacidad
/// aprobado por compliance debajo. El sync del widget reescribe el snapshot
/// en el acto al cambiar.
class WidgetPositionsTile extends ConsumerWidget {
  const WidgetPositionsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(widgetPositionsHiddenProvider);
    return SettingsToggleRow(
      icon: Icons.visibility_off_outlined,
      label: 'home_widget_hide_positions'.tr(),
      // Texto de compliance: se lee entero, aun en iPhone SE.
      subtitle: 'home_widget_positions_privacy_note'.tr(),
      subtitleMaxLines: null,
      value: hidden,
      onChanged: (value) {
        ref.read(widgetPositionsHiddenProvider.notifier).setHidden(value);
        ref.read(productEventsProvider).log(ProductEvent.widgetPositionsToggled, {
          'hidden': value,
        });
      },
    );
  }
}
