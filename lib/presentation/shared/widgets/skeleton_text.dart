import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Texto que puede no estar todavía. Sin [text] muestra una barra quieta
/// (sin shimmer: nada que compita con el resto) del tamaño exacto que
/// ocupa [placeholder] con el mismo [style], así el skeleton tiene la
/// altura final y el cambio a datos no mueve el layout.
///
/// Con [animate], cada cambio de valor (barra → texto, o un número que se
/// refresca en el lugar) hace un crossfade corto en vez de saltar.
class SkeletonText extends StatelessWidget {
  const SkeletonText(
    this.text, {
    super.key,
    this.style,
    this.placeholder = '\$0,000.00',
    this.animate = false,
  });

  final String? text;
  final TextStyle? style;
  final String placeholder;
  final bool animate;

  static const duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final value = text;
    final Widget child =
        value == null
            ? _Bar(
              key: const ValueKey<Object>(_Bar),
              placeholder: placeholder,
              style: style,
            )
            : Text(value, key: ValueKey<Object>(value), style: style);
    if (!animate) return child;
    return AnimatedSwitcher(
      duration:
          MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      layoutBuilder:
          (current, previous) => Stack(
            alignment: Alignment.centerRight,
            children: [...previous, if (current != null) current],
          ),
      child: child,
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({super.key, required this.placeholder, required this.style});

  final String placeholder;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      child: Stack(
        children: [
          // Invisible: solo da el tamaño.
          Opacity(opacity: 0, child: Text(placeholder, style: style)),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.customColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
