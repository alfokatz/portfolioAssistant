import 'package:flutter/material.dart';

/// Fade de entrada corto (sin traslación) para un mensaje recién agregado a
/// la lista del chat. Es intencionalmente distinto de [FadeSlideIn]: acá no
/// hay desplazamiento espacial — el mensaje ya nace en su posición final, y
/// esto solo suaviza el corte de aparición (swap instantáneo con un fade
/// muy corto encima, no una animación de "viaje").
///
/// Como el `ListView` de la pantalla del asistente no reconstruye tiles ya
/// montados (misma key), este fade corre una sola vez, exactamente cuando
/// el mensaje aparece por primera vez — nunca para mensajes existentes.
class MessageAppearFade extends StatefulWidget {
  const MessageAppearFade({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 90),
    this.skipAnimation = false,
  });

  final Widget child;
  final Duration duration;

  /// `true` si este mensaje ya terminó de aparecer en un montaje anterior
  /// (ver `PortfolioQaMessage.hasRevealed` / `AssistantState.introRevealed`)
  /// — remontar (p. ej. tras scrollear fuera del viewport y volver) no debe
  /// repetir el fade. Parámetro explícito, no una `MediaQuery` ambient
  /// override: ver el comentario en `TypewriterText.skipAnimation`.
  final bool skipAnimation;

  @override
  State<MessageAppearFade> createState() => _MessageAppearFadeState();
}

class _MessageAppearFadeState extends State<MessageAppearFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.skipAnimation || MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      child: widget.child,
    );
  }
}
