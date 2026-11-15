import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/notifications/data/push_messaging.dart';
import 'package:portfolio_assistant/features/notifications/providers/push_controller.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_says.dart';

/// Por qué se ofrece el permiso: cambia el texto (plan §6, siempre en un
/// momento en que aporta valor).
enum PushPromptReason {
  priceAlert,
  weeklyReport,
  etoro,
  settings,
  diagnosis,

  /// Al entrar a la Home (la primera vez y, si dijo "Ahora no", cada tanto).
  welcome,
}

/// La pantalla previa al diálogo del sistema. iOS deja mostrar ese diálogo
/// UNA vez: si el usuario no quiere, que diga "Ahora no" acá y no allá.
class PushPermissionSheet extends ConsumerWidget {
  const PushPermissionSheet({super.key, required this.reason});

  final PushPromptReason reason;

  /// Muestra la hoja si corresponde (permiso sin decidir, y la política de
  /// insistencia lo permite) y devuelve el permiso final. Con
  /// [force] (desde Ajustes) se muestra aunque la política diga que no.
  static Future<PushPermission> maybeShow(
    BuildContext context,
    WidgetRef ref, {
    required PushPromptReason reason,
    bool force = false,
  }) async {
    final controller = ref.read(pushControllerProvider.notifier);
    await controller.refreshPermission();
    final permission = ref.read(pushControllerProvider).permission;
    // Ya respondió el diálogo del sistema (o no hay push): nada que ofrecer.
    if (permission != PushPermission.notDetermined) return permission;
    final policy = ref.read(pushPromptPolicyProvider);
    if (!force && !policy.shouldOffer(permission)) return permission;
    if (!context.mounted) return permission;

    await policy.recordShown();
    if (!context.mounted) return permission;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => PushPermissionSheet(reason: reason),
    );
    final events = ref.read(productEventsProvider);
    if (accepted != true) {
      await policy.recordDismissed();
      events.log(ProductEvent.pushOptIn, {
        'source': reason.name,
        'result': 'dismissed',
      });
      return permission;
    }
    final result = await controller.requestPermission();
    events.log(ProductEvent.pushOptIn, {
      'source': reason.name,
      'result':
          result == PushPermission.granted ||
                  result == PushPermission.provisional
              ? 'granted'
              : 'denied',
    });
    return result;
  }

  String get _titleKey => switch (reason) {
    PushPromptReason.priceAlert => 'push_prompt_title_price_alert',
    PushPromptReason.weeklyReport => 'push_prompt_title_weekly_report',
    PushPromptReason.etoro => 'push_prompt_title_etoro',
    PushPromptReason.settings => 'push_prompt_title_settings',
    PushPromptReason.diagnosis => 'push_prompt_title_diagnosis',
    PushPromptReason.welcome => 'push_prompt_title_welcome',
  };

  String get _bodyKey => switch (reason) {
    PushPromptReason.priceAlert => 'push_prompt_body_price_alert',
    PushPromptReason.weeklyReport => 'push_prompt_body_weekly_report',
    PushPromptReason.etoro => 'push_prompt_body_etoro',
    PushPromptReason.settings => 'push_prompt_body_settings',
    PushPromptReason.diagnosis => 'push_prompt_body_diagnosis',
    PushPromptReason.welcome => 'push_prompt_body_welcome',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) => PushSheetLayout(
    title: _titleKey.tr(),
    body: _bodyKey.tr(),
    actionLabel: 'push_prompt_enable'.tr(),
  );
}

/// La forma de las hojas de notificaciones: Porty pregunta con su cara
/// ([PortySays]), las tres promesas (control, silencio, privacidad) y la
/// acción. `pop(true)` con la acción, `pop(false)` con "Ahora no".
class PushSheetLayout extends StatelessWidget {
  const PushSheetLayout({
    super.key,
    required this.title,
    required this.body,
    required this.actionLabel,
    this.mood = PortyAvatarState.idle,
  });

  final String title;
  final String body;
  final String actionLabel;
  final PortyAvatarState mood;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final text = Theme.of(context).textTheme;

    Widget point(IconData icon, String key) => Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.sp12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppDimens.iconMd, color: colors.accentBlue),
          const SizedBox(width: AppDimens.sp12),
          Expanded(
            child: Text(
              key.tr(),
              style: text.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          0,
          AppDimens.pageHorizontal,
          AppDimens.sp16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PortySays(
              messageKey: title,
              mood: mood,
              message: Semantics(header: true, child: Text(title)),
              footnote: Text(body),
            ),
            const SizedBox(height: AppDimens.sp20),
            Padding(
              // Las promesas, alineadas con el texto de Porty.
              padding: const EdgeInsets.only(
                left: PortySays.avatarSize + AppDimens.sp12,
              ),
              child: Column(
                children: [
                  point(Icons.tune_rounded, 'push_prompt_point_control'),
                  point(Icons.bedtime_outlined, 'push_prompt_point_quiet'),
                  point(
                    Icons.lock_outline_rounded,
                    'push_prompt_point_privacy',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimens.sp12),
            PositionPrimaryButton(
              label: actionLabel,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: AppDimens.sp4),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  minimumSize: const Size(
                    AppDimens.touchTarget,
                    AppDimens.touchTarget,
                  ),
                ),
                child: Text('push_prompt_not_now'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
