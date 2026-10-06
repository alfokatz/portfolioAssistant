import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';

/// Espera sin estructura conocida (arranque, Porty escribiendo el informe,
/// una pantalla que todavía no tiene nada que mostrar): Porty pensando,
/// centrado, y si la espera pasa de [LoaderTiming.messageDelay], una línea
/// debajo con fade. Nada de spinner.
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
    this.size = defaultSize,
    this.messageDelay = LoaderTiming.messageDelay,
    this.textColor,
    this.semanticsLabel,
  });

  /// La línea que aparece si la espera se alarga. `null`: solo Porty.
  final String? message;
  final double size;
  final Duration messageDelay;

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

  @override
  State<PortyLoader> createState() => _PortyLoaderState();
}

class _PortyLoaderState extends State<PortyLoader> {
  // Arranca en reposo (como el splash) y pasa a pensar en el primer frame:
  // así la expresión y la inclinación entran con su transición en vez de
  // aparecer de golpe.
  PortyAvatarState _state = PortyAvatarState.idle;
  bool _showMessage = false;
  Timer? _messageTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _state = PortyAvatarState.thinking);
    });
    _messageTimer = Timer(widget.messageDelay, () {
      if (mounted) setState(() => _showMessage = true);
    });
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final showMessage = _showMessage && message != null;
    final label = [
      widget.semanticsLabel ?? 'loading'.tr(),
      if (showMessage) message,
    ].join(', ');

    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: Column(
        children: [
          const Spacer(),
          PortyAvatar(state: _state, size: widget.size, animated: true),
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
                  child: Text(
                    message ?? '',
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
        ],
      ),
    );
  }
}
