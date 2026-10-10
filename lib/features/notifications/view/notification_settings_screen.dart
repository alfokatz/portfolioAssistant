import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;
import 'package:portfolio_assistant/features/notifications/data/notifications_repository.dart';
import 'package:portfolio_assistant/features/notifications/data/push_messaging.dart';
import 'package:portfolio_assistant/features/notifications/domain/notification_preferences.dart';
import 'package:portfolio_assistant/features/notifications/nav/notifications_router.dart';
import 'package:portfolio_assistant/features/notifications/providers/notification_preferences_provider.dart';
import 'package:portfolio_assistant/features/notifications/providers/push_controller.dart';
import 'package:portfolio_assistant/features/notifications/view/push_permission_sheet.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_nav_row.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_picker_sheet.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_section_card.dart';

/// Ajustes → Notificaciones: el permiso del sistema, qué tipos recibir,
/// sensibilidad de los movimientos, horario de silencio y montos.
class NotificationSettingsScreen extends StatefulHookConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends BaseStatefulWidget<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  // Se empuja por encima del shell, que ya escucha las alertas globales.
  @override
  bool get subscribesToGlobalEvents => false;

  bool _sendingTest = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    runAfterPostFrameCallback(() {
      ref.read(notificationPreferencesProvider.notifier).load();
      ref.read(pushControllerProvider.notifier).syncToken();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Vuelve de los ajustes del teléfono: el permiso pudo cambiar.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(pushControllerProvider.notifier).syncToken();
    }
  }

  void _update(NotificationPreferences Function(NotificationPreferences) f) {
    ref.read(notificationPreferencesProvider.notifier).update(f).then((_) {
      if (!mounted) return;
      if (ref.read(notificationPreferencesProvider).saveFailed) {
        ref
            .read(alertProvider.notifier)
            .showError(message: 'notifications_save_error'.tr());
      }
    });
  }

  Future<void> _enable() async {
    await PushPermissionSheet.maybeShow(
      context,
      ref,
      reason: PushPromptReason.settings,
      force: true,
    );
  }

  Future<void> _sendTest() async {
    setState(() => _sendingTest = true);
    try {
      await ref.read(pushControllerProvider.notifier).syncToken();
      await ref.read(notificationsRepositoryProvider).requestTestNotification();
      if (!mounted) return;
      ref
          .read(alertProvider.notifier)
          .showSuccess(message: 'notifications_test_sent'.tr());
    } catch (_) {
      if (!mounted) return;
      ref
          .read(alertProvider.notifier)
          .showError(message: 'notifications_test_error'.tr());
    } finally {
      if (mounted) setState(() => _sendingTest = false);
    }
  }

  Future<void> _pickSensitivity(BigMoveSensitivity current) async {
    final selected = await showModalBottomSheet<BigMoveSensitivity>(
      context: context,
      builder:
          (ctx) => SettingsPickerSheet(
            title: 'notifications_sensitivity'.tr(),
            children: [
              for (final s in BigMoveSensitivity.values)
                SettingsPickerOption(
                  label:
                      '${'notifications_sensitivity_${s.name}'.tr()} · '
                      '${'notifications_sensitivity_${s.name}_desc'.tr()}',
                  isSelected: s == current,
                  onTap: () => Navigator.of(ctx).pop(s),
                ),
            ],
          ),
    );
    if (selected != null) {
      _update((p) => p.copyWith(bigMoveSensitivity: selected));
    }
  }

  Future<void> _pickQuiet({required bool start}) async {
    final prefs = ref.read(notificationPreferencesProvider).preferences;
    final minutes = start ? prefs.quietStartMinutes : prefs.quietEndMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      helpText:
          (start
                  ? 'notifications_quiet_from'
                  : 'notifications_quiet_until')
              .tr(),
    );
    if (picked == null) return;
    final value = picked.hour * 60 + picked.minute;
    _update(
      (p) =>
          start
              ? p.copyWith(quietStartMinutes: value)
              : p.copyWith(quietEndMinutes: value),
    );
  }

  @override
  Widget buildView(BuildContext context) {
    final push = ref.watch(pushControllerProvider);
    final prefsState = ref.watch(notificationPreferencesProvider);
    final prefs = prefsState.preferences;
    final colors = context.customColors;
    final canReceive = push.permission.canReceive;
    final typesEnabled = canReceive && prefs.enabled && prefsState.loaded;

    ValueChanged<bool>? toggle(
      NotificationPreferences Function(NotificationPreferences, bool) f,
    ) => typesEnabled ? (v) => _update((p) => f(p, v)) : null;

    return Scaffold(
      appBar: AppBar(title: Text('notifications_title'.tr())),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            AppDimens.sp8,
            AppDimens.pageHorizontal,
            AppDimens.sp48,
          ),
          children: [
            Text(
              'notifications_intro'.tr(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppDimens.sp20),
            _PermissionSection(
              permission: push.permission,
              loaded: push.loaded,
              enabled: prefs.enabled,
              onEnable: _enable,
              onToggle:
                  prefsState.loaded
                      ? (v) => _update((p) => p.copyWith(enabled: v))
                      : null,
            ),
            const SizedBox(height: AppDimens.sectionGap),
            SettingsSectionCard(
              title: 'notifications_section_what'.tr(),
              children: [
                SettingsToggleRow(
                  icon: Icons.notifications_active_outlined,
                  label: 'notifications_price_alerts'.tr(),
                  subtitle: 'notifications_price_alerts_desc'.tr(),
                  value: prefs.priceAlerts,
                  onChanged: toggle((p, v) => p.copyWith(priceAlerts: v)),
                ),
                const SettingsDivider(),
                SettingsNavRow(
                  icon: Icons.list_alt_rounded,
                  label: 'price_alerts_title'.tr(),
                  onTap:
                      () => context.pushNamed(
                        NotificationsRouter.alertsRouteName,
                      ),
                ),
                const SettingsDivider(),
                SettingsToggleRow(
                  icon: Icons.trending_up_rounded,
                  label: 'notifications_big_moves'.tr(),
                  subtitle: 'notifications_big_moves_desc'.tr(),
                  value: prefs.bigMoves,
                  onChanged: toggle((p, v) => p.copyWith(bigMoves: v)),
                ),
                const SettingsDivider(),
                SettingsToggleRow(
                  icon: Icons.pie_chart_outline_rounded,
                  label: 'notifications_portfolio_moves'.tr(),
                  subtitle: 'notifications_portfolio_moves_desc'.tr(),
                  value: prefs.portfolioMoves,
                  onChanged: toggle((p, v) => p.copyWith(portfolioMoves: v)),
                ),
                const SettingsDivider(),
                SettingsToggleRow(
                  icon: Icons.event_note_outlined,
                  label: 'notifications_weekly_report'.tr(),
                  subtitle: 'notifications_weekly_report_desc'.tr(),
                  value: prefs.weeklyReport,
                  onChanged: toggle((p, v) => p.copyWith(weeklyReport: v)),
                ),
                const SettingsDivider(),
                SettingsToggleRow(
                  icon: Icons.insights_outlined,
                  label: 'notifications_earnings'.tr(),
                  subtitle: 'notifications_earnings_desc'.tr(),
                  value: prefs.earnings,
                  onChanged: toggle((p, v) => p.copyWith(earnings: v)),
                ),
                const SettingsDivider(),
                SettingsToggleRow(
                  icon: Icons.manage_accounts_outlined,
                  label: 'notifications_service'.tr(),
                  subtitle: 'notifications_service_desc'.tr(),
                  value: prefs.service,
                  onChanged: toggle((p, v) => p.copyWith(service: v)),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.sectionGap),
            SettingsSectionCard(
              title: 'notifications_section_how'.tr(),
              children: [
                SettingsNavRow(
                  icon: Icons.speed_rounded,
                  label: 'notifications_sensitivity'.tr(),
                  value:
                      'notifications_sensitivity_${prefs.bigMoveSensitivity.name}'
                          .tr(),
                  onTap:
                      typesEnabled
                          ? () => _pickSensitivity(prefs.bigMoveSensitivity)
                          : null,
                ),
                const SettingsDivider(),
                SettingsNavRow(
                  icon: Icons.bedtime_outlined,
                  label: 'notifications_quiet_from'.tr(),
                  value: NotificationPreferences.formatClock(
                    prefs.quietStartMinutes,
                  ),
                  onTap: typesEnabled ? () => _pickQuiet(start: true) : null,
                ),
                const SettingsDivider(),
                SettingsNavRow(
                  icon: Icons.wb_twilight_rounded,
                  label: 'notifications_quiet_until'.tr(),
                  value: NotificationPreferences.formatClock(
                    prefs.quietEndMinutes,
                  ),
                  onTap: typesEnabled ? () => _pickQuiet(start: false) : null,
                ),
                const SettingsDivider(),
                SettingsToggleRow(
                  icon: Icons.attach_money_rounded,
                  label: 'notifications_show_amounts'.tr(),
                  subtitle: 'notifications_show_amounts_desc'.tr(),
                  value: prefs.showAmounts,
                  onChanged: toggle((p, v) => p.copyWith(showAmounts: v)),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.sp4,
                AppDimens.sp8,
                AppDimens.sp4,
                0,
              ),
              child: Text(
                prefs.hasQuietHours
                    ? 'notifications_quiet_note'.tr()
                    : 'notifications_quiet_off_note'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
            if (canReceive) ...[
              const SizedBox(height: AppDimens.sp20),
              Center(
                child: TextButton.icon(
                  onPressed: _sendingTest ? null : _sendTest,
                  icon: const Icon(Icons.send_rounded, size: AppDimens.iconSm),
                  label: Text('notifications_send_test'.tr()),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(
                      AppDimens.touchTarget,
                      AppDimens.touchTarget,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// El estado del permiso del sistema y el interruptor general.
class _PermissionSection extends StatelessWidget {
  const _PermissionSection({
    required this.permission,
    required this.loaded,
    required this.enabled,
    required this.onEnable,
    required this.onToggle,
  });

  final PushPermission permission;
  final bool loaded;
  final bool enabled;
  final VoidCallback onEnable;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final Widget row = switch (permission) {
      _ when !loaded => SettingsNavRow(
        icon: Icons.notifications_none_rounded,
        label: 'notifications_master'.tr(),
        onTap: null,
        showChevron: false,
      ),
      PushPermission.granted || PushPermission.provisional => SettingsToggleRow(
        icon: Icons.notifications_none_rounded,
        label: 'notifications_master'.tr(),
        value: enabled,
        onChanged: onToggle,
      ),
      PushPermission.notDetermined => SettingsNavRow(
        icon: Icons.notifications_none_rounded,
        label: 'notifications_enable'.tr(),
        subtitle: 'notifications_enable_desc'.tr(),
        onTap: onEnable,
      ),
      PushPermission.denied => SettingsNavRow(
        icon: Icons.notifications_off_outlined,
        label: 'notifications_denied'.tr(),
        subtitle: 'notifications_denied_desc'.tr(),
        onTap: openAppSettings,
      ),
      PushPermission.unavailable => SettingsNavRow(
        icon: Icons.notifications_off_outlined,
        label: 'notifications_unavailable'.tr(),
        subtitle: 'notifications_unavailable_desc'.tr(),
        onTap: null,
        showChevron: false,
      ),
    };
    return SettingsSectionCard(
      title: 'notifications_section_status'.tr(),
      children: [row],
    );
  }
}
