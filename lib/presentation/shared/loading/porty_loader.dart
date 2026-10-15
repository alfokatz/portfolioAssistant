import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';

/// Espera sin estructura conocida (arranque, Porty escribiendo el informe,
/// una pantalla que todavía no tiene nada que mostrar): Porty pensando,
/// centrado, y si la espera pasa de [messageDelay], una línea debajo con
/// fade. Con [messages], la línea va rotando cada [messageInterval]. Nada de
/// spinner.
///
/// El avatar queda en el centro exacto del espacio que le dan (la línea se
/// dibuja debajo sin moverlo): es el mismo lugar y tamaño que el splash
/// nativo, así splash → loader → pantalla es continuo.
///
/// No aplica la regla de los 300 ms por sí solo: para eso, ponerlo dentro
/// de un `LoadingSwitcher`. El arranque lo muestra directo porque continúa
/// al splash, que ya tiene a Porty en pantalla.
class PortyLoader extends StatefulWidget {
  const PortyLoader({
    super.key,
    this.message,
    this.messages,
    this.size = defaultSize,
    this.messageDelay = LoaderTiming.messageDelay,
    this.messageInterval = defaultMessageInterval,
    this.thinkingStyle = PortyThinkingStyle.standard,
    this.textColor,
    this.semanticsLabel,
  }) : assert(
         message == null || messages == null,
         'message o messages, no los dos',
       );

  /// La línea que aparece si la espera se alarga. `null`: solo Porty.
  final String? message;

  /// Varias líneas que se turnan (en orden, en loop) cada
  /// [messageInterval], con fade. Reemplaza a [message].
  final List<String>? messages;
  final double size;
  final Duration messageDelay;
  final Duration messageInterval;

  /// Cómo piensa Porty mientras espera. [PortyThinkingStyle.pulse] (se
  /// achica y se agranda) en el arranque.
  final PortyThinkingStyle thinkingStyle;

  /// Por defecto `textSecondary`. Hace falta fuera de un `MaterialApp` con
  /// el tema de la app (el arranque).
  final Color? textColor;

  /// Por defecto `'loading'.tr()`; el arranque lo pasa resuelto porque
  /// todavía no hay traducciones cargadas.
  final String? semanticsLabel;

  /// Caja del avatar (el cuerpo mide ~70 %, ver `PortyAvatar.size`). El
  /// splash nativo usa el mismo tamaño.
  static const defaultSize = 64.0;

  /// Aire entre Porty y la línea.
  static const messageGap = 16.0;

  /// Cuánto queda cada línea de [messages] antes de dar paso a la próxima.
  static const defaultMessageInterval = Duration(milliseconds: 2800);

  /// Fundido entre una línea y la siguiente.
  static const messageSwap = Duration(milliseconds: 450);

  @override
  State<PortyLoader> createState() => _PortyLoaderState();
}

class _PortyLoaderState extends State<PortyLoader> {
  // Arranca en reposo (como el splash) y pasa a pensar en el primer frame:
  // así la expresión y la inclinación entran con su transición en vez de
  // aparecer de golpe.
  PortyAvatarState _state = PortyAvatarState.idle;
  bool _showMessage = false;
  int _index = 0;
  Timer? _messageTimer;
  Timer? _rotateTimer;

  List<String> get _lines =>
      widget.messages ?? [if (widget.message case final m?) m];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _state = PortyAvatarState.thinking);
    });
    _messageTimer = Timer(widget.messageDelay, () {
      if (!mounted) return;
      setState(() => _showMessage = true);
      _rotateTimer = Timer.periodic(widget.messageInterval, (_) {
        final count = _lines.length;
        if (mounted && count > 1) setState(() => _index = (_index + 1) % count);
      });
    });
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _rotateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    final message = lines.isEmpty ? null : lines[_index % lines.length];
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final showMessage = _showMessage && message != null;
    // Solo la primera línea: si cada cambio se anunciara, el lector de
    // pantalla hablaría cada pocos segundos.
    final label = [
      widget.semanticsLabel ?? 'loading'.tr(),
      if (showMessage) lines.first,
    ].join(', ');

    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: Column(
        children: [
          const Spacer(),
          PortyAvatar(
            state: _state,
            size: widget.size,
            animated: true,
            thinkingStyle: widget.thinkingStyle,
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  32,
                  PortyLoader.messageGap,
                  32,
                  0,
                ),
                child: AnimatedOpacity(
                  opacity: showMessage ? 1 : 0,
                  duration:
                      reduceMotion ? Duration.zero : LoaderTiming.swap * 2,
                  curve: Curves.easeOut,
                  // Cada línea nueva entra subiendo apenas mientras la
                  // anterior se desvanece.
                  child: AnimatedSwitcher(
                    duration:
                        reduceMotion ? Duration.zero : PortyLoader.messageSwap,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder:
                        (current, previous) => Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            ...previous,
                            if (current != null) current,
                          ],
                        ),
                    transitionBuilder:
                        (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0, 0.35),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                    child: Text(
                      message ?? '',
                      key: ValueKey(_index),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color:
                            widget.textColor ??
                            context.customColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
