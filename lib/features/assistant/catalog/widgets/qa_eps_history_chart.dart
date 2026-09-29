import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Un trimestre del historial de EPS.
class QaEpsQuarter {
  const QaEpsQuarter({
    required this.label,
    required this.actual,
    required this.estimate,
  });

  final String label;
  final double actual;
  final double estimate;

  bool get beat => actual >= estimate;

  /// Sorpresa sobre el consenso, en %; `null` si el consenso es 0.
  double? get surprisePct =>
      estimate == 0 ? null : (actual - estimate) / estimate.abs() * 100;
}

/// Gráfico de "sorpresas" de EPS, el que usan Robinhood/Quartz para
/// earnings: por trimestre, el consenso como círculo hueco y el real como
/// punto lleno (verde si superó, rojo si no), unidos por un trazo que hace
/// visible la distancia. Debajo, período, EPS real y sorpresa en texto —
/// el color nunca es la única señal.
///
/// Al aparecer, cada punto real "sale" desde el consenso hasta su valor:
/// la animación cuenta exactamente la historia de la sorpresa.
class QaEpsHistoryChart extends StatelessWidget {
  const QaEpsHistoryChart({super.key, required this.quarters});

  /// Del más viejo al más nuevo.
  final List<QaEpsQuarter> quarters;

  static const _plotHeight = 96.0;

  @override
  Widget build(BuildContext context) {
    if (quarters.isEmpty) return const SizedBox.shrink();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _plotHeight,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
            duration: const Duration(milliseconds: 750),
            curve: Curves.easeOutCubic,
            builder:
                (context, t, _) => CustomPaint(
                  size: Size.infinite,
                  painter: _EpsPainter(quarters: quarters, progress: t),
                ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final q in quarters)
              Expanded(child: _QuarterCaption(quarter: q)),
          ],
        ),
      ],
    );
  }
}

class _QuarterCaption extends StatelessWidget {
  const _QuarterCaption({required this.quarter});

  final QaEpsQuarter quarter;

  @override
  Widget build(BuildContext context) {
    final surprise = quarter.surprisePct;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          quarter.label,
          style: QaText.caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(QaFormat.price(quarter.actual), style: QaText.valueSm),
        if (surprise != null) ...[
          const SizedBox(height: 2),
          Text(
            QaFormat.signedPct(surprise, digits: 1),
            style: QaText.caption.copyWith(
              color: QaPalette.trend(surprise),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// Leyenda compacta ("● Real  ○ Estimado") para el trailing del rótulo de
/// sección.
class QaEpsLegend extends StatelessWidget {
  const QaEpsLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget dot({required bool hollow}) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hollow ? null : PortfolioColors.textPrimary,
        border:
            hollow
                ? Border.all(color: PortfolioColors.textSecondary, width: 1.5)
                : null,
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(hollow: false),
        const SizedBox(width: 4),
        const Text('Real', style: QaText.caption),
        const SizedBox(width: 10),
        dot(hollow: true),
        const SizedBox(width: 4),
        const Text('Estimado', style: QaText.caption),
      ],
    );
  }
}

class _EpsPainter extends CustomPainter {
  _EpsPainter({required this.quarters, required this.progress});

  final List<QaEpsQuarter> quarters;
  final double progress;

  static const _radius = 5.5;

  @override
  void paint(Canvas canvas, Size size) {
    final values = [
      for (final q in quarters) ...[q.actual, q.estimate],
    ];
    var minV = values.reduce(math.min);
    var maxV = values.reduce(math.max);
    // Margen para que los puntos no toquen el borde; con todos los valores
    // iguales se abre un rango artificial y quedan centrados.
    final span = maxV - minV;
    final pad =
        span.abs() < 1e-9 ? math.max(maxV.abs() * 0.2, 0.1) : span * 0.2;
    minV -= pad;
    maxV += pad;
    final top = _radius + 2;
    final bottom = size.height - _radius - 2;
    double y(double v) => bottom - (v - minV) / (maxV - minV) * (bottom - top);

    // Guías horizontales tenues; si el rango cruza cero, la línea de 0 se
    // marca un poco más (EPS negativo = pérdida).
    final grid =
        Paint()
          ..color = PortfolioColors.border
          ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final gy = top + (bottom - top) * i / 2;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }
    if (minV < 0 && maxV > 0) {
      canvas.drawLine(
        Offset(0, y(0)),
        Offset(size.width, y(0)),
        Paint()
          ..color = PortfolioColors.textSecondary.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
    }

    final colWidth = size.width / quarters.length;
    for (var i = 0; i < quarters.length; i++) {
      final q = quarters[i];
      final x = colWidth * (i + 0.5);
      final estY = y(q.estimate);
      final actY = estY + (y(q.actual) - estY) * progress;
      final color = q.beat ? PortfolioColors.profit : PortfolioColors.loss;

      if ((actY - estY).abs() > _radius * 2) {
        canvas.drawLine(
          Offset(x, estY + (actY > estY ? _radius : -_radius)),
          Offset(x, actY + (actY > estY ? -_radius : _radius)),
          Paint()
            ..color = color.withValues(alpha: 0.35)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
      }

      canvas.drawCircle(
        Offset(x, estY),
        _radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = PortfolioColors.textSecondary,
      );
      // Anillo blanco: separa el punto real del consenso cuando se solapan.
      canvas.drawCircle(
        Offset(x, actY),
        _radius + 1.5,
        Paint()..color = PortfolioColors.surfaceCard,
      );
      canvas.drawCircle(Offset(x, actY), _radius, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_EpsPainter old) =>
      old.progress != progress || old.quarters != quarters;
}
