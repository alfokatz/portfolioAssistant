import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Barra horizontal con el centro en 0: hacia la derecha en verde si
/// [value] es positivo, hacia la izquierda en rojo si es negativo. La fila
/// con el mayor valor absoluto ([maxAbs]) llega al borde.
class DivergingBar extends StatelessWidget {
  const DivergingBar({
    super.key,
    required this.value,
    required this.maxAbs,
    this.height = 6,
  });

  final double value;
  final double maxAbs;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final share = maxAbs <= 0 ? 0.0 : (value.abs() / maxAbs).clamp(0.0, 1.0);
    final color = colors.pnlColor(value).withValues(alpha: 0.8);
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, c) {
            final half = c.maxWidth / 2;
            // Aunque el valor sea mínimo, que se vea para qué lado fue.
            final width = math.max(half * share, share > 0 ? 3.0 : 0.0);
            return Stack(
              children: [
                // El eje: una línea fina de lado a lado y una marca en 0.
                Positioned(
                  left: 0,
                  right: 0,
                  top: height / 2 - 0.5,
                  height: 1,
                  child: ColoredBox(color: colors.border),
                ),
                Positioned(
                  left: half - 0.5,
                  width: 1,
                  top: 0,
                  bottom: 0,
                  child: ColoredBox(color: colors.border),
                ),
                Positioned(
                  left: value >= 0 ? half : half - width,
                  width: width,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(height / 2),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
