import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Indicador de espera del asistente: un orbe que respira mientras la IA
/// procesa. Reemplaza el `CircularProgressIndicator` estático en todo punto
/// de espera del flujo (servicio inicializando, streaming de una respuesta).
///
/// Un solo tono de [PortfolioColors.accentBlue] con un halo sutil — sin
/// gradientes ni colores nuevos — animado con un ciclo orgánico de
/// escala + opacidad. Respeta `disableAnimations` (reduced motion).
class AssistantThinkingOrb extends StatefulWidget {
  const AssistantThinkingOrb({super.key, this.size = 20});

  final double size;

  @override
  State<AssistantThinkingOrb> createState() => _AssistantThinkingOrbState();
}

class _AssistantThinkingOrbState extends State<AssistantThinkingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  static const _minScale = 0.85;
  static const _maxScale = 1.15;
  static const _minOpacity = 0.55;
  static const _maxOpacity = 0.9;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `MediaQuery.disableAnimationsOf` depends on an inherited widget, which
    // can't be read from `initState`; `didChangeDependencies` is the earliest
    // safe place, gated so it only starts the loop once.
    if (_started) return;
    _started = true;
    if (!MediaQuery.disableAnimationsOf(context)) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return _orb(scale: 1, opacity: _maxOpacity);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOutSine.transform(_controller.value);
        return _orb(
          scale: lerpDouble(_minScale, _maxScale, t)!,
          opacity: lerpDouble(_minOpacity, _maxOpacity, t)!,
        );
      },
    );
  }

  Widget _orb({required double scale, required double opacity}) {
    const color = PortfolioColors.accentBlue;
    return SizedBox(
      width: widget.size * _maxScale,
      height: widget.size * _maxScale,
      child: Center(
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: opacity),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: opacity * 0.45),
                  blurRadius: widget.size * 0.85,
                  spreadRadius: widget.size * 0.05,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
