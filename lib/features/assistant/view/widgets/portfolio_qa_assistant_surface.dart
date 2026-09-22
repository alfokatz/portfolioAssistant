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
  });

  final String surfaceId;
  final SurfaceContext surfaceContext;

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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _revealController = SurfaceRevealController(reduceMotion: reduceMotion);
    if (reduceMotion) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          child: SurfaceRevealScope(
            controller: _revealController,
            child: Surface(
              key: ValueKey(widget.surfaceId),
              surfaceContext: widget.surfaceContext,
            ),
          ),
        ),
      ),
    );
  }
}
