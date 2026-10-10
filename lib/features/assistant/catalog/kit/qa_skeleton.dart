import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/presentation/shared/loading/skeleton.dart';

/// Tiempos de los skeletons y transiciones de estado del kit.
abstract final class QaStateMotion {
  /// Cambio de estado de una sección (bloqueada → con datos, texto que
  /// aparece/desaparece): el espacio se ajusta y el contenido hace
  /// crossfade con la misma duración, así lo de abajo se desliza.
  static const change = Duration(milliseconds: 240);
  static const curve = Curves.easeOutCubic;

  /// Pulso de los skeletons (el mismo de toda la app).
  static const shimmer = SkeletonMotion.pulse;
}

/// Líneas grises redondeadas en lugar de un contenido que todavía no está.
/// Sin texto ni números — nunca aparenta un dato. Son los bloques
/// compartidos de la app (`SkeletonBlock`) con el color del kit: mismo
/// pulso lento y, con reduce motion, estático. No se anuncia por su cuenta
/// (la card o el precio que lo contiene ya lo hace).
class QaSkeleton extends StatelessWidget {
  const QaSkeleton({super.key, this.lines = 2, this.widths = const []});

  final int lines;

  /// Ancho relativo de cada línea (0..1); por defecto la última es más corta.
  final List<double> widths;

  double _width(int i) {
    if (i < widths.length) return widths[i];
    return i == lines - 1 && lines > 1 ? 0.6 : 1;
  }

  @override
  Widget build(BuildContext context) {
    return SkeletonScope(
      announce: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < lines; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            FractionallySizedBox(
              widthFactor: _width(i),
              child: SkeletonBlock.line(color: QaPalette.inset),
            ),
          ],
        ],
      ),
    );
  }
}
