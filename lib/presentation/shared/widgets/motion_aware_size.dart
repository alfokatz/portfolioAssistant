import 'package:flutter/material.dart';

/// [AnimatedSize] que respeta reduce motion. Con animaciones desactivadas no
/// envuelve al hijo: un `AnimatedSize` con duración cero se re-ensucia en su
/// propio layout (assert de Flutter). La [GlobalKey] conserva el estado del
/// hijo si el setting cambia con la pantalla abierta.
class MotionAwareSize extends StatefulWidget {
  const MotionAwareSize({
    super.key,
    required this.duration,
    required this.child,
    this.curve = Curves.easeOutCubic,
    this.alignment = Alignment.topCenter,
  });

  final Duration duration;
  final Curve curve;
  final AlignmentGeometry alignment;
  final Widget child;

  @override
  State<MotionAwareSize> createState() => _MotionAwareSizeState();
}

class _MotionAwareSizeState extends State<MotionAwareSize> {
  final _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedSize(
      duration: widget.duration,
      curve: widget.curve,
      alignment: widget.alignment,
      child: child,
    );
  }
}
