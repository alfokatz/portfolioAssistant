import 'package:flutter/material.dart';

/// Revela [text] carácter por carácter, simulando un typewriter, a un ritmo
/// de lectura natural (`charsPerSecond`). No hay streaming real de tokens
/// desde el backend — esto es una simulación puramente client-side, una vez
/// que el texto final ya está disponible por completo.
///
/// Accesibilidad: el texto COMPLETO va siempre en el nodo de semantics,
/// desde el primer frame — un lector de pantalla no debe esperar a que
/// termine la animación visual para tener el contenido entero. La porción
/// animada se excluye de semantics para no duplicar/confundir la lectura.
///
/// Reduced motion: se salta la animación y se muestra el texto completo de
/// inmediato (mismo criterio que el resto de las animaciones de esta app).
class TypewriterText extends StatefulWidget {
  const TypewriterText({
    super.key,
    required this.text,
    this.style,
    this.charsPerSecond = 40,
    this.onComplete,
    this.play = true,
  });

  final String text;
  final TextStyle? style;
  final double charsPerSecond;
  final VoidCallback? onComplete;

  /// Si es `false`, el widget queda "pausado" en 0 caracteres visibles
  /// hasta que pase a `true` — usado por [RevealStep] para esperar su turno
  /// antes de empezar a tipear.
  final bool play;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _durationFor(widget.text, widget.charsPerSecond),
    )..addStatusListener(_handleStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeStart();
  }

  @override
  void didUpdateWidget(covariant TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _started = false;
      _completed = false;
      _controller.duration = _durationFor(widget.text, widget.charsPerSecond);
      _controller.reset();
    }
    _maybeStart();
  }

  void _maybeStart() {
    if (_started || !widget.play) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_completed) {
      _completed = true;
      widget.onComplete?.call();
    }
  }

  static Duration _durationFor(String text, double charsPerSecond) {
    if (text.isEmpty || charsPerSecond <= 0) return Duration.zero;
    final ms = (text.length / charsPerSecond * 1000).round();
    return Duration(milliseconds: ms.clamp(1, 1000 * 60));
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.text,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final visibleChars = (widget.text.length * _controller.value)
              .floor()
              .clamp(0, widget.text.length);
          return ExcludeSemantics(
            child: Text(
              widget.text.substring(0, visibleChars),
              style: widget.style,
            ),
          );
        },
      ),
    );
  }
}
