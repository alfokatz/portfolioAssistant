import 'package:easy_localization/easy_localization.dart';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/utils/porty_activity_copy.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/turn_activity.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Consultas que le quedan al usuario en el período de su plan.
class PortyQuota {
  const PortyQuota({required this.remaining, required this.limit});

  final int remaining;
  final int limit;

  /// Aviso con el 10% de la cuota o menos (free: 2 de 20; premium: 50 de
  /// 500; gold: 100 de 1000).
  bool get isLow => remaining <= (limit * lowFraction).ceil();

  static const lowFraction = 0.1;
}

/// Top bar de la pantalla de Porty: identidad (avatar + nombre), una línea
/// de estado que sigue al turno en curso ([activity]) y, a la derecha, las
/// consultas restantes.
///
/// El avatar respira y parpadea en reposo; durante un turno no actúa (lo
/// hace el avatar del mensaje, ver `AssistantScreen`): lo que cambia es la
/// línea de estado. [mood], si se pasa, fija su expresión. Tocarlo lo hace
/// mirar hacia el toque, con un haptic leve.
///
/// El header es transparente sobre `AppBackgroundGradient`; el borde contra
/// el chat lo resuelve el fade de la lista (ver `AssistantScreen`), no una
/// línea ni una superficie propia.
class PortyHeader extends StatefulWidget {
  const PortyHeader({
    super.key,
    required this.activity,
    this.mood,
    this.entrance = false,
    this.quota,
    this.onQuotaTap,
  });

  final ValueListenable<TurnActivity> activity;

  final ValueListenable<PortyAvatarState>? mood;

  /// El avatar aparece con su entrada (primera vez del chat en la sesión).
  final bool entrance;

  /// `null` oculta el chip.
  final PortyQuota? quota;

  /// `null` deja el chip no interactivo.
  final VoidCallback? onQuotaTap;

  static const avatarSize = PortyAvatar.defaultSize;

  @override
  State<PortyHeader> createState() => _PortyHeaderState();
}

class _PortyHeaderState extends State<PortyHeader> {
  static const _statusFade = Duration(milliseconds: 200);
  static const _topPadding = AppDimens.sp8;
  static const _nameFontSize = 17.0;
  static const _nameHeight = 1.2;
  static const _nameLineHeight = _nameFontSize * _nameHeight;
  static const _statusFontSize = 13.0;
  static const _statusHeight = 1.3;
  static const _nameStatusGap = 3.0;

  /// Alto del bloque nombre + estado, para alinear el chip con el nombre
  /// (el avatar es más alto y la fila centra el texto).
  static const _textHeight =
      _nameLineHeight + _nameStatusGap + _statusFontSize * _statusHeight;
  static final _textTop = math.max(
    0.0,
    (PortyHeader.avatarSize - _textHeight) / 2,
  );

  // Se fija en initState (no lazy): si se leyera recién en el primer cambio
  // de actividad, ya valdría el estado nuevo y el anuncio no saldría.
  late bool _busy;

  @override
  void initState() {
    super.initState();
    _busy = !widget.activity.value.isIdle;
    widget.activity.addListener(_onActivity);
  }

  @override
  void didUpdateWidget(PortyHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activity != widget.activity) {
      oldWidget.activity.removeListener(_onActivity);
      widget.activity.addListener(_onActivity);
      _onActivity();
    }
  }

  @override
  void dispose() {
    widget.activity.removeListener(_onActivity);
    super.dispose();
  }

  void _onActivity() {
    final busy = !widget.activity.value.isIdle;
    if (busy == _busy) return;
    _busy = busy;
    if (busy) _announceStart();
  }

  /// Una sola vez por turno: los cambios de tool actualizan el label del
  /// header pero no se anuncian (interrumpirían a VoiceOver cada segundo).
  void _announceStart() {
    if (!MediaQuery.of(context).accessibleNavigation) return;
    SemanticsService.sendAnnouncement(
      View.of(context),
      'porty_status_announcement'.tr(),
      Directionality.of(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final quota = widget.quota;

    // El chip va arriba a la derecha, a la altura del nombre, en vez de en
    // la fila: así la línea de estado usa todo el ancho y el ticker no se
    // trunca. Su área táctil de 44 px cae dentro del header (por eso el
    // padding superior de 12: centra la píldora con el nombre).
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            _topPadding,
            AppDimens.pageHorizontal,
            AppDimens.sp4,
          ),
          child: ValueListenableBuilder<TurnActivity>(
            valueListenable: widget.activity,
            builder: (context, activity, _) {
              final status = PortyActivityCopy.describe(activity);
              final name = 'portfolio_qa_title'.tr();
              return Semantics(
                container: true,
                header: true,
                label: '$name, $status',
                excludeSemantics: true,
                child: Row(
                  children: [
                    _HeaderAvatar(
                      mood: widget.mood,
                      entrance: widget.entrance,
                    ),
                    const SizedBox(width: AppDimens.sp12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            style: textTheme.titleMedium?.copyWith(
                              fontSize: _nameFontSize,
                              fontWeight: FontWeight.w600,
                              height: _nameHeight,
                              letterSpacing: -0.25,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: _nameStatusGap),
                          AnimatedSwitcher(
                            duration:
                                reduceMotion ? Duration.zero : _statusFade,
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeOutCubic,
                            layoutBuilder:
                                (current, previous) => Stack(
                                  alignment: Alignment.centerLeft,
                                  children: [
                                    ...previous,
                                    if (current != null) current,
                                  ],
                                ),
                            child: Text(
                              status,
                              key: ValueKey(status),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                fontSize: _statusFontSize,
                                fontWeight: FontWeight.w500,
                                height: _statusHeight,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (quota != null)
          Positioned(
            top:
                _topPadding +
                _textTop +
                _nameLineHeight / 2 -
                AppDimens.touchTarget / 2,
            right: AppDimens.pageHorizontal,
            child: _QuotaChip(quota: quota, onTap: widget.onQuotaTap),
          ),
      ],
    );
  }
}

class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar({required this.mood, required this.entrance});

  final ValueListenable<PortyAvatarState>? mood;
  final bool entrance;

  @override
  Widget build(BuildContext context) {
    Widget avatar(PortyAvatarState state) => PortyAvatar(
      state: state,
      size: PortyHeader.avatarSize,
      animated: true,
      entrance: entrance,
      onTap: () => PortyHapticsService.maybeOf(context)?.selectionTap(),
    );
    final mood = this.mood;
    if (mood == null) return avatar(PortyAvatarState.idle);
    return ValueListenableBuilder<PortyAvatarState>(
      valueListenable: mood,
      builder: (context, state, _) => avatar(state),
    );
  }
}

class _QuotaChip extends StatelessWidget {
  const _QuotaChip({required this.quota, this.onTap});

  final PortyQuota quota;
  final VoidCallback? onTap;

  static const _height = 24.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final low = quota.isLow;
    final background = low ? colors.lossContainer : colors.surfaceElevated;
    final foreground = low ? colors.loss : colors.textSecondary;

    final pill = AnimatedContainer(
      duration:
          MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      height: _height,
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.sp12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(_height / 2),
      ),
      child: Text(
        'porty_quota_remaining'.tr(namedArgs: {'count': '${quota.remaining}'}),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.0,
          letterSpacing: 0.1,
          color: foreground,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );

    return Semantics(
      container: true,
      button: onTap != null,
      label: 'porty_quota_semantics'.tr(
        namedArgs: {'count': '${quota.remaining}', 'limit': '${quota.limit}'},
      ),
      onTapHint: onTap != null ? 'porty_quota_tap_hint'.tr() : null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // Área táctil de 44 px alrededor de la píldora de 28.
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppDimens.touchTarget,
            minWidth: AppDimens.touchTarget,
          ),
          child: Center(widthFactor: 1, child: pill),
        ),
      ),
    );
  }
}
