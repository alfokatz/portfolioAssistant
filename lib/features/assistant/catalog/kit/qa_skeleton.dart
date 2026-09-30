import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';

/// Tiempos de los skeletons y transiciones de estado del kit.
abstract final class QaStateMotion {
  /// Cambio de estado de una sección (bloqueada → con datos, texto que
  /// aparece/desaparece): el espacio se ajusta y el contenido hace
  /// crossfade con la misma duración, así lo de abajo se desliza.
  static const change = Duration(milliseconds: 240);
  static const curve = Curves.easeOutCubic;

  /// Shimmer muy lento: se nota que carga sin llamar la atención.
  static const shimmer = Duration(milliseconds: 1600);
}

/// Líneas grises redondeadas en lugar de un contenido que todavía no está.
/// Sin texto ni números — nunca aparenta un dato. Con animaciones, un
/// shimmer lento de opacidad (0,55 ↔ 1); con reduce motion, estático.
class QaSkeleton extends StatefulWidget {
  const QaSkeleton({super.key, this.lines = 2, this.widths = const []});

  final int lines;

  /// Ancho relativo de cada línea (0..1); por defecto la última es más corta.
  final List<double> widths;

  @override
  State<QaSkeleton> createState() => _QaSkeletonState();
}

class _QaSkeletonState extends State<QaSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: QaStateMotion.shimmer,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _shimmer
        ..stop()
        ..value = 1;
    } else if (!_shimmer.isAnimating) {
      _shimmer.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  double _width(int i) {
    if (i < widget.widths.length) return widget.widths[i];
    return i == widget.lines - 1 && widget.lines > 1 ? 0.6 : 1;
  }

  @override
  Widget build(BuildContext context) {
    final color = QaPalette.inset;
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: Tween<double>(
          begin: 0.55,
          end: 1,
        ).animate(CurvedAnimation(parent: _shimmer, curve: Curves.easeInOut)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.lines; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              FractionallySizedBox(
                widthFactor: _width(i),
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
