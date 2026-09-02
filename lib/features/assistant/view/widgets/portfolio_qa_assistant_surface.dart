import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Burbuja del asistente que renderiza una surface GenUI.
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
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _entrance = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `MediaQuery.disableAnimationsOf` depends on an inherited widget, which
    // can't be read from `initState`; `didChangeDependencies` is the earliest
    // safe place, gated so the entrance only fires once.
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
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
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.92,
        ),
        child: FadeTransition(
          opacity: _entrance,
          child: AnimatedBuilder(
            animation: _entrance,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, (1 - _entrance.value) * 8),
              child: child,
            ),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: PortfolioColors.surfaceCard,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(14),
                ),
                border: Border.all(color: PortfolioColors.border),
              ),
              child: Surface(
                key: ValueKey(widget.surfaceId),
                surfaceContext: widget.surfaceContext,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
