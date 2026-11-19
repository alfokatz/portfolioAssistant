import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_prompt_provider.dart';
import 'package:portfolio_assistant/features/notifications/data/push_messaging.dart';
import 'package:portfolio_assistant/features/notifications/providers/push_controller.dart';
import 'package:portfolio_assistant/features/notifications/view/push_permission_sheet.dart';
import 'package:portfolio_assistant/features/notifications/view/push_settings_sheet.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/providers/portfolio_diagnosis_provider.dart';

/// Ofrece las notificaciones al entrar a la Home:
/// - sin decidir: la hoja de siempre ([PushPermissionSheet], motivo
///   `welcome`). La primera vez apenas llega a la Home; si dice "Ahora no",
///   [PushPromptPolicy] decide cuándo volver (hasta 3 veces, cada 14 días).
/// - rechazado en el diálogo del sistema: [PushSettingsSheet], que lleva a los
///   ajustes del teléfono, con [PushSettingsReminderPolicy].
///
/// Para no apilar avisos (igual que el del widget): solo con la Home a la
/// vista y nada encima, después de [settleDelay], una vez por apertura, no en
/// la apertura en la que se vio el primer diagnóstico (ese ya ofrece las
/// notificaciones) ni si el aviso del widget ya salió en esta apertura.
class PushReminderWatcher extends ConsumerStatefulWidget {
  const PushReminderWatcher({
    super.key,
    required this.isHome,
    required this.child,
    this.settleDelay = const Duration(milliseconds: 1500),
  });

  final bool isHome;
  final Widget child;
  final Duration settleDelay;

  @override
  ConsumerState<PushReminderWatcher> createState() =>
      _PushReminderWatcherState();
}

class _PushReminderWatcherState extends ConsumerState<PushReminderWatcher> {
  Timer? _timer;
  bool _triedThisOpen = false;
  bool _diagnosisThisOpen = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _onTop => ModalRoute.of(context)?.isCurrent ?? true;

  bool get _blocked =>
      _triedThisOpen ||
      _diagnosisThisOpen ||
      !widget.isHome ||
      ref.read(widgetPromptProvider).offeredThisOpen;

  Future<void> _try() async {
    _timer = null;
    if (!mounted || _blocked || !_onTop) return;
    _triedThisOpen = true;

    final controller = ref.read(pushControllerProvider.notifier);
    await controller.refreshPermission();
    if (!mounted) return;
    final permission = ref.read(pushControllerProvider).permission;
    final reminders = ref.read(pushSettingsReminderPolicyProvider);
    await reminders.observe(permission);
    if (!mounted || !widget.isHome || !_onTop) return;

    if (permission == PushPermission.notDetermined) {
      if (!ref.read(pushPromptPolicyProvider).shouldOffer(permission)) return;
      ref.read(homePromptShownThisOpenProvider.notifier).state = true;
      await PushPermissionSheet.maybeShow(
        context,
        ref,
        reason: PushPromptReason.welcome,
      );
    } else if (reminders.shouldOffer(permission)) {
      ref.read(homePromptShownThisOpenProvider.notifier).state = true;
      await reminders.recordShown();
      if (!mounted) return;
      await PushSettingsSheet.show(context, ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(diagnosisSeenProvider, (previous, next) {
      if (previous == false && next) _diagnosisThisOpen = true;
    });
    final ready = widget.isHome && !_triedThisOpen && !_diagnosisThisOpen;
    if (ready && _timer == null) {
      _timer = Timer(widget.settleDelay, _try);
    } else if (!ready) {
      _timer?.cancel();
      _timer = null;
    }
    return widget.child;
  }
}
