import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/notifications/view/push_permission_sheet.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';

/// Para quien rechazó el permiso en el diálogo del sistema: iOS no deja
/// volver a mostrarlo, así que lo único que se puede hacer es llevarlo a los
/// ajustes del teléfono. Misma forma que [PushPermissionSheet]
/// ([PushSheetLayout]).
class PushSettingsSheet extends StatelessWidget {
  const PushSettingsSheet({super.key});

  /// Muestra la hoja y, si toca "Abrir ajustes", abre los ajustes de la app
  /// en el teléfono. [openSettings] es la costura para tests.
  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    Future<bool> Function() openSettings = openAppSettings,
  }) async {
    final open = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const PushSettingsSheet(),
    );
    ref.read(productEventsProvider).log(ProductEvent.pushOptIn, {
      'source': 'settings_reminder',
      'result': open == true ? 'opened_settings' : 'dismissed',
    });
    if (open == true) await openSettings();
  }

  @override
  Widget build(BuildContext context) => PushSheetLayout(
    title: 'push_reminder_title'.tr(),
    body: 'push_reminder_body'.tr(),
    actionLabel: 'push_reminder_open_settings'.tr(),
    // Apenas preocupado: se está perdiendo los avisos, no es un error.
    mood: PortyAvatarState.concerned,
  );
}
