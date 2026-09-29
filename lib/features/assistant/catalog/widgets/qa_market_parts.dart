import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/services/price_chart_data_loader.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Piezas compartidas por las cards de mercado (gráfico de precio,
/// comparativo, snapshot/movimiento): selector de período, tag de peso en
/// el portfolio, fechas y rótulos de rango. Viven acá y no en el kit
/// porque dependen de [PriceChartRange].
abstract final class QaMarketParts {
  static const monthsEs = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  /// Fecha de un punto del gráfico: hora en 1D, día + mes + año en el resto.
  static String formatDate(DateTime date, PriceChartRange range) {
    if (range == PriceChartRange.day) {
      final h = date.hour.toString().padLeft(2, '0');
      final m = date.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${date.day} ${monthsEs[date.month - 1]} ${date.year}';
  }

  static String rangeSummaryLabel(PriceChartRange range) => switch (range) {
    PriceChartRange.day => 'Hoy',
    PriceChartRange.week => 'Última semana',
    PriceChartRange.month => 'Último mes',
    PriceChartRange.quarter => 'Últimos 3 meses',
    PriceChartRange.year => 'Último año',
    PriceChartRange.all => 'Todo el histórico',
  };

  /// "12% de tu portfolio" — un decimal solo por debajo de 10%, donde la
  /// diferencia entre 2% y 2,5% todavía importa.
  static String weightLabel(double weightPct) =>
      '${QaFormat.pct(weightPct, digits: weightPct >= 10 ? 0 : 1)} '
      'de tu portfolio';

  /// Tag de peso para el trailing de un header de ticker; `null` si el
  /// usuario no lo tiene.
  static Widget? weightTag(double weightPct) =>
      weightPct > 0
          ? QaTag(weightLabel(weightPct), icon: Icons.pie_chart_outline_rounded)
          : null;

  /// Primera letra en mayúscula ("últimos 7 días" → "Últimos 7 días"): los
  /// `label_es` de las tools vienen en minúscula para ir en mitad de frase.
  static String capitalize(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  /// Parsea el número de un valor que el modelo ya formateó como texto
  /// ("+1,2%", "-\$7", "38,2%"). `null` si no hay número.
  static double? parseLooseNumber(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'[^0-9,.\-−+]'), '')
        .replaceAll('−', '-');
    if (cleaned.isEmpty) return null;
    // "1.234,5" (es) y "1,234.5" (en): el último separador es el decimal.
    final lastComma = cleaned.lastIndexOf(',');
    final lastDot = cleaned.lastIndexOf('.');
    String normalized;
    if (lastComma > lastDot) {
      normalized = cleaned.replaceAll('.', '').replaceAll(',', '.');
    } else {
      normalized = cleaned.replaceAll(',', '');
    }
    return double.tryParse(normalized);
  }

  /// Si el valor viene con signo explícito es una variación (P&L, cambio
  /// de precio) y se pinta con profit/loss; si no, es una magnitud neutra.
  static bool isSignedValue(String text) =>
      RegExp(r'^\s*[+\-−]').hasMatch(text);

  /// Un label que parece ticker ("AAPL", "BRK.B", "^GSPC") y no un rótulo
  /// de métrica ("Valor", "P&L %").
  static bool looksLikeTicker(String text) =>
      RegExp(r'^[A-Z0-9^][A-Z0-9.\-^]{0,9}$').hasMatch(text.trim());
}

/// Selector de período como control segmentado tenue: un track gris con
/// el período elegido en una "pastilla" blanca. Cada segmento ocupa el
/// mismo ancho y tiene ≥ 36px de alto para el dedo.
class QaRangeTabs extends StatelessWidget {
  const QaRangeTabs({
    super.key,
    required this.ranges,
    required this.selected,
    required this.onSelected,
  });

  final List<PriceChartRange> ranges;
  final PriceChartRange selected;
  final ValueChanged<PriceChartRange> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: QaPalette.inset,
        borderRadius: BorderRadius.circular(QaSpace.chipRadius + 2),
      ),
      child: Row(
        children: [
          for (final range in ranges)
            Expanded(
              child: Semantics(
                button: true,
                selected: range == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelected(range),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color:
                          range == selected
                              ? PortfolioColors.surfaceCard
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(QaSpace.chipRadius),
                      border: Border.all(
                        color:
                            range == selected
                                ? PortfolioColors.border
                                : Colors.transparent,
                      ),
                      boxShadow:
                          range == selected
                              ? const [
                                BoxShadow(
                                  color: Color(0x0D000000),
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ]
                              : null,
                    ),
                    child: Text(
                      range.label,
                      style: QaText.caption.copyWith(
                        fontSize: 12,
                        color:
                            range == selected
                                ? PortfolioColors.textPrimary
                                : PortfolioColors.textSecondary,
                        fontWeight:
                            range == selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Spinner chico y neutro para el área de un gráfico mientras carga.
class QaChartSpinner extends StatelessWidget {
  const QaChartSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: PortfolioColors.textSecondary,
        ),
      ),
    );
  }
}

/// Dibuja una línea horizontal punteada — la referencia de "inicio del
/// período" en los gráficos.
void paintDashedHorizontal(
  Canvas canvas, {
  required double y,
  required double width,
  required Color color,
  double dash = 3,
  double gap = 3,
}) {
  final paint =
      Paint()
        ..color = color
        ..strokeWidth = 1;
  for (var x = 0.0; x < width; x += dash + gap) {
    canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(0, width), y), paint);
  }
}
