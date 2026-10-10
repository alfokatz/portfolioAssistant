import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_data.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_type.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Las alertas de la app (éxito, aviso, error): una tarjeta arriba, debajo de
/// la barra de estado, con Porty contento, neutro o apenas triste. Entra con
/// un fade y una bajada corta, queda unos segundos y se va con un fade
/// (tocarla la cierra antes). Una sola a la vez: la nueva reemplaza a la
/// anterior. Reemplaza al SnackBar verde/rojo de antes.
abstract final class PortyToast {
  static const visibleFor = Duration(milliseconds: 2800);
  static const enter = Duration(milliseconds: 260);
  static const exit = Duration(milliseconds: 220);

  static OverlayEntry? _current;

  static void show(BuildContext context, AlertData alert) {
    final text = [
      if (alert.title?.isNotEmpty == true) alert.title!,
      if (alert.message?.isNotEmpty == true) alert.message!,
    ];
    if (text.isEmpty) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _current?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder:
          (_) => _ToastHost(
            alert: alert,
            onGone: () {
              if (_current == entry) _current = null;
              if (entry.mounted) entry.remove();
            },
          ),
    );
    _current = entry;
    overlay.insert(entry);

    final haptics = PortyHapticsService.maybeOf(context);
    switch (alert.alertType) {
      case AlertType.success:
        haptics?.authSucceeded();
      case AlertType.error:
        haptics?.authFailed();
      case AlertType.warning:
        break;
    }
    SemanticsService.announce(text.join('. '), Directionality.of(context));
  }
}

class _ToastHost extends StatefulWidget {
  const _ToastHost({required this.alert, required this.onGone});

  final AlertData alert;
  final VoidCallback onGone;

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: PortyToast.enter,
    reverseDuration: PortyToast.exit,
  );
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(PortyToast.visibleFor, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer?.cancel();
    await _controller.reverse();
    widget.onGone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) _controller.value = _leaving ? 0 : 1;
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return Positioned(
      left: AppDimens.pageHorizontal,
      right: AppDimens.pageHorizontal,
      top: MediaQuery.paddingOf(context).top + AppDimens.sp8,
      child: FadeTransition(
        opacity: curved,
        child: AnimatedBuilder(
          animation: curved,
          builder:
              (context, child) => Transform.translate(
                offset: Offset(0, reduceMotion ? 0 : -12 * (1 - curved.value)),
                child: child,
              ),
          child: GestureDetector(
            onTap: _dismiss,
            // Deslizar hacia arriba también la cierra.
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < 0) _dismiss();
            },
            child: _ToastCard(alert: widget.alert),
          ),
        ),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.alert});

  final AlertData alert;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final title = alert.title?.isNotEmpty == true ? alert.title : null;
    final message = alert.message?.isNotEmpty == true ? alert.message : null;
    final (mood, accent) = switch (alert.alertType) {
      AlertType.success => (PortyAvatarState.answered, colors.profit),
      AlertType.error => (PortyAvatarState.concerned, colors.loss),
      AlertType.warning => (PortyAvatarState.idle, colors.accentBlue),
    };

    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.sp12,
          AppDimens.sp12,
          AppDimens.sp16,
          AppDimens.sp12,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: BorderRadius.circular(AppDimens.radiusXl),
          border: Border.all(color: colors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 18,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: PortyAvatar(size: 36, state: mood, animated: true),
            ),
            const SizedBox(width: AppDimens.sp12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(
                      title,
                      style: tt.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (message != null)
                    Text(
                      message,
                      style: (title == null ? tt.bodyMedium : tt.bodySmall)
                          ?.copyWith(
                            color:
                                title == null
                                    ? colors.textPrimary
                                    : colors.textSecondary,
                            fontWeight: title == null ? FontWeight.w600 : null,
                            height: 1.35,
                          ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppDimens.sp8),
            // Un punto del color del tipo: se lee éxito / error de un vistazo
            // sin teñir toda la tarjeta.
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}
