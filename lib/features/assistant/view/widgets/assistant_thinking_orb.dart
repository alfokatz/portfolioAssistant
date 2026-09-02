import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Indicador de espera del asistente: un orbe que respira y flota mientras
/// la IA procesa. Reemplaza el `CircularProgressIndicator` estático en todo
/// punto de espera del flujo (servicio inicializando, streaming de una
/// respuesta) — sin chrome de burbuja alrededor, para que se sienta suelto
/// en la pantalla en vez de encerrado en un contenedor.
///
/// Un solo tono de [PortfolioColors.accentBlue] con un halo sutil — sin
/// gradientes ni colores nuevos. Dos ciclos independientes (respiración de
/// escala/opacidad y deriva vertical) con duraciones distintas para que la
/// combinación no se sienta mecánica. Respeta `disableAnimations` (reduced
/// motion).
class AssistantThinkingOrb extends StatefulWidget {
  const AssistantThinkingOrb({super.key, this.size = 20});

  final double size;

  @override
  State<AssistantThinkingOrb> createState() => _AssistantThinkingOrbState();
}

class _AssistantThinkingOrbState extends State<AssistantThinkingOrb>
    with TickerProviderStateMixin {
  late final AnimationController _breathController;
  late final AnimationController _driftController;
  bool _started = false;

  static const _minScale = 0.85;
  static const _maxScale = 1.15;
  static const _minOpacity = 0.55;
  static const _maxOpacity = 0.9;

  double get _driftAmplitude => widget.size * 0.22;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    // Duración deliberadamente distinta a la de respiración: al no ser
    // múltiplos entre sí, la fase relativa entre ambos ciclos va corriendo
    // en vez de repetirse siempre igual — se siente orgánico, no mecánico.
    _driftController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
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
      _breathController.repeat(reverse: true);
      _driftController.repeat();
    }
  }

  @override
  void dispose() {
    _breathController.dispose();
    _driftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return _orb(scale: 1, opacity: _maxOpacity, dy: 0);
    }
    return AnimatedBuilder(
      animation: Listenable.merge([_breathController, _driftController]),
      builder: (context, _) {
        final breathT = Curves.easeInOutSine.transform(_breathController.value);
        final driftT = _driftController.value;
        return _orb(
          scale: lerpDouble(_minScale, _maxScale, breathT)!,
          opacity: lerpDouble(_minOpacity, _maxOpacity, breathT)!,
          dy: math.sin(driftT * 2 * math.pi) * _driftAmplitude,
        );
      },
    );
  }

  Widget _orb({required double scale, required double opacity, required double dy}) {
    const color = PortfolioColors.accentBlue;
    final bounds = widget.size * _maxScale + _driftAmplitude * 2;
    return SizedBox(
      width: bounds,
      height: bounds,
      child: Center(
        child: Transform.translate(
          offset: Offset(0, dy),
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
      ),
    );
  }
}
