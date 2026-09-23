import 'package:flutter/material.dart';

/// Staggered entrance reveal: fades in and rises slightly. Used for content
/// that appears once (welcome state, suggestion prompts) so the screen
/// doesn't just snap into existence — each [delay] offsets the start so a
/// list of these reads as a cascade rather than a uniform flash.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 360),
    this.skipAnimation = false,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// `true` si esta entrada ya se mostró en un montaje anterior (ver
  /// `AssistantState.introRevealed`) — remontar no debe repetirla.
  /// Parámetro explícito, no una `MediaQuery` ambient override: ver el
  /// comentario en `TypewriterText.skipAnimation`.
  final bool skipAnimation;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curved;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.skipAnimation || MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      child: widget.child,
      builder:
          (context, child) => Opacity(
            opacity: _curved.value,
            child: Transform.translate(
              offset: Offset(0, (1 - _curved.value) * 10),
              child: child,
            ),
          ),
    );
  }
}
