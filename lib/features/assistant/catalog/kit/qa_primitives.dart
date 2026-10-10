import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/reveal_step.dart';

/// Chip de variación: ▲/▼ + porcentaje (o monto) sobre un fondo teñido del
/// color semántico. Es la forma única de mostrar "subió/bajó" en el kit.
class QaDeltaChip extends StatelessWidget {
  const QaDeltaChip({
    super.key,
    required this.value,
    this.text,
    this.digits = 2,
    this.dense = false,
  });

  /// Signo que decide color y flecha.
  final num value;

  /// Texto a mostrar; default: [value] como porcentaje con signo.
  final String? text;
  final int digits;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = QaPalette.trend(value);
    final isFlat = value == 0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: isFlat ? QaPalette.track : QaPalette.trendTint(value),
        borderRadius: BorderRadius.circular(QaSpace.chipRadius - 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isFlat) ...[
            Icon(
              value > 0
                  ? Icons.arrow_drop_up_rounded
                  : Icons.arrow_drop_down_rounded,
              size: dense ? 14 : 16,
              color: color,
            ),
            const SizedBox(width: 1),
          ],
          Text(
            text ??
                QaFormat.signedPct(
                  value,
                  digits: digits,
                ).replaceAll('+', '').replaceAll('-', ''),
            style: (dense ? QaText.caption : QaText.valueSm).copyWith(
              color: isFlat ? QaColors.textSecondary : color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip neutro para metadatos o estados ("T3 FY26", "Antes de apertura",
/// "Fit 70"). [color] tiñe el texto y el fondo.
class QaTag extends StatelessWidget {
  const QaTag(this.text, {super.key, this.color, this.icon});

  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? QaColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color == null ? QaPalette.track : fg.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(QaSpace.chipRadius - 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QaText.caption.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bloque interno teñido: agrupa un sub-contenido dentro de una card sin
/// anidar otra card con borde (evita "cards dentro de cards").
class QaInset extends StatelessWidget {
  const QaInset({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? QaPalette.inset,
        borderRadius: BorderRadius.circular(QaSpace.insetRadius),
      ),
      child: child,
    );
  }
}

/// Rótulo + valor, apilados. La unidad mínima de las grillas de métricas.
class QaStat extends StatelessWidget {
  const QaStat({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.trailing,
    this.large = false,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final Widget? trailing;
  final bool large;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final style = (large ? QaText.displaySm : QaText.value).copyWith(
      color: valueColor,
    );
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: QaText.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing!],
          ],
        ),
      ],
    );
  }
}

/// Grilla de [QaStat] en N columnas de ancho igual, filas separadas solo
/// por espacio. Ocupa siempre el ancho completo de la card.
class QaStatGrid extends StatelessWidget {
  const QaStatGrid({super.key, required this.stats, this.columns = 2});

  final List<QaStat> stats;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final rows = <List<QaStat>>[
      for (var i = 0; i < stats.length; i += columns)
        stats.sublist(i, math.min(i + columns, stats.length)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: QaSpace.rowGap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < columns; c++)
                Expanded(
                  child: c < rows[r].length ? rows[r][c] : const SizedBox(),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class QaDivider extends StatelessWidget {
  const QaDivider({super.key, this.vertical = 0, this.indent = 0});

  final double vertical;
  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: vertical),
      child: Divider(
        height: 1,
        thickness: 1,
        color: QaColors.border,
        indent: indent,
        endIndent: indent,
      ),
    );
  }
}

/// Etiqueta de contexto en mayúsculas y terracota ("ÚLTIMOS 7 DÍAS"), con
/// un trailing opcional. Va arriba del número o bloque que contextualiza.
/// Para encabezar una sección de la card, [QaSectionTitle] / [QaSection].
class QaSectionLabel extends StatelessWidget {
  const QaSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(text.toUpperCase(), style: QaText.eyebrow)),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Título de una sección de la card ("Puntos clave"), en minúsculas y con
/// un trailing opcional (leyenda, sparkline, tag).
class QaSectionTitle extends StatelessWidget {
  const QaSectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(text, style: QaText.sectionTitle),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Una sección de la card: una línea fina arriba (salvo [first]), el título
/// y el contenido. Es la única forma de separar con línea dentro de una
/// card: las filas de adentro van separadas solo por espacio.
class QaSection extends StatelessWidget {
  const QaSection({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.first = false,
  });

  /// Sin título: solo la línea y el aire (p. ej. un disclaimer al pie).
  final String? title;
  final Widget? trailing;
  final Widget child;

  /// La primera sección después del encabezado: sin línea, solo aire.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (first)
          const SizedBox(height: QaSpace.sectionGap)
        else
          const QaDivider(vertical: QaSpace.sectionDividerGap),
        if (title != null) ...[
          QaSectionTitle(title, trailing: trailing),
          const SizedBox(height: QaSpace.gap),
        ],
        child,
      ],
    );
  }
}

/// Barra de progreso redondeada sobre un track tenue.
class QaProgressBar extends StatelessWidget {
  const QaProgressBar({
    super.key,
    required this.value,
    Color? color,
    this.height = 6,
  }) : _color = color;

  /// 0..1
  final double value;
  final Color? _color;
  Color get color => _color ?? QaColors.accentBlue;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: EntranceFill(
          duration: const Duration(milliseconds: 700),
          builder:
              (context, t, _) => Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: QaPalette.track)),
                  FractionallySizedBox(
                    widthFactor: value.clamp(0.0, 1.0) * t,
                    child: ColoredBox(color: color),
                  ),
                ],
              ),
        ),
      ),
    );
  }
}

/// Un segmento de [QaSegmentedBar].
class QaSegment {
  const QaSegment({required this.value, required this.color});
  final double value;
  final Color color;
}

/// Barra apilada horizontal con pequeños cortes entre segmentos — la
/// representación de "cómo se reparte un total" (portfolio, presupuesto).
class QaSegmentedBar extends StatelessWidget {
  const QaSegmentedBar({super.key, required this.segments, this.height = 10});

  final List<QaSegment> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (a, s) => a + math.max(0, s.value));
    if (total <= 0) {
      return QaProgressBar(value: 0, height: height);
    }
    return EntranceFill(
      duration: const Duration(milliseconds: 800),
      builder:
          (context, t, _) => SizedBox(
            height: height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const gap = 2.0;
                final usable =
                    constraints.maxWidth -
                    gap * math.max(0, segments.length - 1);
                return Row(
                  children: [
                    for (var i = 0; i < segments.length; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      Container(
                        width: math.max(
                          0,
                          usable * segments[i].value / total * t,
                        ),
                        decoration: BoxDecoration(
                          color: segments[i].color,
                          borderRadius: BorderRadius.horizontal(
                            left: Radius.circular(i == 0 ? height : 2),
                            right: Radius.circular(
                              i == segments.length - 1 ? height : 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
    );
  }
}

/// Anillo de progreso (o donut de un solo valor) con contenido al centro.
class QaRing extends StatelessWidget {
  const QaRing({
    super.key,
    required this.value,
    this.size = 64,
    this.stroke = 7,
    Color? color,
    this.center,
  }) : _color = color;

  /// 0..1
  final double value;
  final double size;
  final double stroke;
  final Color? _color;
  Color get color => _color ?? QaColors.accentBlue;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: EntranceFill(
        duration: RevealTiming.fill,
        builder:
            (context, t, child) => CustomPaint(
              painter: _RingPainter(
                segments: [
                  QaSegment(value: value.clamp(0.0, 1.0) * t, color: color),
                ],
                total: 1,
                stroke: stroke,
              ),
              child: child,
            ),
        child: center == null ? null : Center(child: center),
      ),
    );
  }
}

/// Donut de varios segmentos con contenido al centro.
class QaDonut extends StatelessWidget {
  const QaDonut({
    super.key,
    required this.segments,
    this.size = 96,
    this.stroke = 12,
    this.center,
  });

  final List<QaSegment> segments;
  final double size;
  final double stroke;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (a, s) => a + math.max(0, s.value));
    return SizedBox.square(
      dimension: size,
      child: EntranceFill(
        duration: const Duration(milliseconds: 900),
        builder:
            (context, t, child) => CustomPaint(
              painter: _RingPainter(
                segments: segments,
                total: total <= 0 ? 1 : total,
                stroke: stroke,
                progress: t,
                gapRadians: segments.length > 1 ? 0.05 : 0,
              ),
              child: child,
            ),
        child: center == null ? null : Center(child: center),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.segments,
    required this.total,
    required this.stroke,
    this.progress = 1,
    this.gapRadians = 0,
  });

  final List<QaSegment> segments;
  final double total;
  final double stroke;
  final double progress;
  final double gapRadians;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - stroke) / 2,
    );
    final track =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = QaPalette.track;
    canvas.drawArc(rect, 0, math.pi * 2, false, track);

    var start = -math.pi / 2;
    final sweepTotal = math.pi * 2 * progress;
    for (final s in segments) {
      final sweep = sweepTotal * (math.max(0, s.value) / total);
      final visible = sweep - gapRadians;
      if (visible > 0) {
        canvas.drawArc(
          rect,
          start + gapRadians / 2,
          visible,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap =
                segments.length == 1 ? StrokeCap.round : StrokeCap.butt
            ..color = s.color,
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.total != total ||
      old.segments != segments;
}

/// Mini gráfico de línea sin ejes para filas y celdas. El color sale de la
/// tendencia (primer vs. último punto) salvo que se fuerce [color].
class QaSparkline extends StatelessWidget {
  const QaSparkline({
    super.key,
    required this.values,
    this.width = 64,
    this.height = 24,
    this.color,
    this.fill = true,
  });

  final List<double> values;
  final double width;
  final double height;
  final Color? color;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(width: width, height: height);
    final c = color ?? QaPalette.trend(values.last - values.first);
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _SparklinePainter(values, c, fill)),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color, this.fill);

  final List<double> values;
  final Color color;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = (maxV - minV).abs() < 1e-9 ? 1.0 : maxV - minV;
    final dx = size.width / (values.length - 1);
    Offset at(int i) => Offset(
      i * dx,
      size.height - 1.5 - (values[i] - minV) / span * (size.height - 3),
    );

    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    if (fill) {
      final area =
          Path.from(line)
            ..lineTo(size.width, size.height)
            ..lineTo(0, size.height)
            ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}

/// Barra de rango (mín–máx) con un marcador en el valor actual — p. ej.
/// rango de 52 semanas o el intervalo de estimaciones de EPS.
class QaRangeBar extends StatelessWidget {
  const QaRangeBar({
    super.key,
    required this.min,
    required this.max,
    required this.value,
    required this.minLabel,
    required this.maxLabel,
  });

  final double min;
  final double max;
  final double value;
  final String minLabel;
  final String maxLabel;

  @override
  Widget build(BuildContext context) {
    final span = max - min;
    final t = span <= 0 ? 0.5 : ((value - min) / span).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 14,
          child: LayoutBuilder(
            builder:
                (context, c) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(
                          colors: [
                            QaColors.loss.withValues(alpha: 0.35),
                            QaColors.profit.withValues(alpha: 0.35),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: (c.maxWidth - 12) * t,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: QaColors.surfaceCard,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: QaColors.textPrimary,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(minLabel, style: QaText.caption),
            const Spacer(),
            Text(maxLabel, style: QaText.caption),
          ],
        ),
      ],
    );
  }
}
