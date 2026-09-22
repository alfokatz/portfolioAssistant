import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/reveal_step.dart';

/// Renderiza la surface GenUI que arma Porty como respuesta.
///
/// Sin chrome de burbuja propio: la surface ya es una `Column` de widgets
/// del catálogo (`qaAnswerText` sin card + tarjetas con `QaCardShell`), y
/// envolverla en una burbuja duplicaba el borde/fondo — quedaba una card
/// blanca dentro de otra card blanca. El texto plano respira en el fondo de
/// la pantalla y las cards marcan su propio borde, como una respuesta de
/// "lenguaje plano" en vez de un bloque de chat encerrado.
///
/// Aparece con un fade + slide-up sutil al montarse: reemplaza al orbe de
/// espera ([AssistantThinkingOrb]) y ese salto merece una transición, no un
/// swap instantáneo.
class PortfolioQaAssistantSurface extends StatefulWidget {
  const PortfolioQaAssistantSurface({
    super.key,
    required this.surfaceId,
    required this.surfaceContext,
    this.onFullyRevealed,
    this.startFullyRevealed = false,
  });

  final String surfaceId;
  final SurfaceContext surfaceContext;

  /// Se llama una sola vez, cuando el último widget de la surface (texto +
  /// cards + chart, lo que haya) termina su propia animación de entrada —
  /// ver [SurfaceRevealController.isFullyRevealed]. Quien escucha (la
  /// pantalla de chat) lo usa para saber exactamente cuándo dejar de
  /// perseguir el fondo del scroll, en vez de adivinarlo.
  final VoidCallback? onFullyRevealed;

  /// `true` si esta surface ya terminó su reveal completo en un montaje
  /// anterior (ver `PortfolioQaMessage.hasRevealed`) — típicamente porque el
  /// mensaje scrolleó fuera del viewport del `ListView` de la pantalla de
  /// chat y volvió a entrar, remontando este widget desde cero. En ese caso
  /// no hay que volver a tipear/animar nada: todo el subárbol se renderiza
  /// en su estado final de una, igual que con `disableAnimations` a nivel
  /// sistema (mismo mecanismo — ver `build`).
  final bool startFullyRevealed;

  @override
  State<PortfolioQaAssistantSurface> createState() =>
      _PortfolioQaAssistantSurfaceState();
}

class _PortfolioQaAssistantSurfaceState
    extends State<PortfolioQaAssistantSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _entrance;
  late final SurfaceRevealController _revealController;
  bool _started = false;
  bool _reportedFullyRevealed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _entrance = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `MediaQuery.disableAnimationsOf` depends on an inherited widget, which
    // can't be read from `initState`; `didChangeDependencies` is the earliest
    // safe place, gated so the entrance/reveal controller only get set up
    // once.
    if (_started) return;
    _started = true;
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) || widget.startFullyRevealed;
    _revealController = SurfaceRevealController(reduceMotion: reduceMotion);
    _revealController.addListener(_handleRevealChanged);
    if (reduceMotion) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  void _handleRevealChanged() {
    if (_reportedFullyRevealed || !_revealController.isFullyRevealed) return;
    _reportedFullyRevealed = true;
    widget.onFullyRevealed?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    _revealController.removeListener(_handleRevealChanged);
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget surface = Surface(
      key: ValueKey(widget.surfaceId),
      surfaceContext: widget.surfaceContext,
    );
    if (widget.startFullyRevealed) {
      // Reusa el mismo interruptor que ya respetan `TypewriterText`,
      // `TwoStageReveal`, `_DefaultFadeStep` y `QaProjectionChart` para
      // accesibilidad (`MediaQuery.disableAnimationsOf`): con esto en
      // `true` cada uno de ellos salta directo a su estado final en vez de
      // animar, sin que este widget tenga que conocer a cada uno.
      surface = MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: surface,
      );
    }
    return FadeTransition(
      opacity: _entrance,
      child: AnimatedBuilder(
        animation: _entrance,
        builder:
            (context, child) => Transform.translate(
              offset: Offset(0, (1 - _entrance.value) * 8),
              child: child,
            ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SurfaceRevealScope(controller: _revealController, child: surface),
        ),
      ),
    );
  }
}
