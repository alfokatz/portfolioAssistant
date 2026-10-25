import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/notifications/data/push_messaging.dart';
import 'package:portfolio_assistant/features/notifications/providers/push_controller.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';

/// Por qué se ofrece el permiso: cambia el texto (plan §6, siempre en un
/// momento en que aporta valor).
enum PushPromptReason { priceAlert, weeklyReport, etoro, settings }

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
    if (accepted != true) {
      await policy.recordDismissed();
      return permission;
    }
    return controller.requestPermission();
  }

  String get _titleKey => switch (reason) {
    PushPromptReason.priceAlert => 'push_prompt_title_price_alert',
    PushPromptReason.weeklyReport => 'push_prompt_title_weekly_report',
    PushPromptReason.etoro => 'push_prompt_title_etoro',
    PushPromptReason.settings => 'push_prompt_title_settings',
  };

  String get _bodyKey => switch (reason) {
    PushPromptReason.priceAlert => 'push_prompt_body_price_alert',
    PushPromptReason.weeklyReport => 'push_prompt_body_weekly_report',
    PushPromptReason.etoro => 'push_prompt_body_etoro',
    PushPromptReason.settings => 'push_prompt_body_settings',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            Semantics(
              header: true,
              child: Text(
                _titleKey.tr(),
                style: text.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: AppDimens.sp8),
            Text(
              _bodyKey.tr(),
              style: text.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppDimens.sp20),
            point(Icons.tune_rounded, 'push_prompt_point_control'),
            point(Icons.bedtime_outlined, 'push_prompt_point_quiet'),
            point(Icons.lock_outline_rounded, 'push_prompt_point_privacy'),
            const SizedBox(height: AppDimens.sp12),
            PositionPrimaryButton(
              label: 'push_prompt_enable'.tr(),
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
