import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';
import 'package:portfolio_assistant/presentation/flows/home/utils/home_chart_utils.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/segmented_choice.dart';
import 'package:portfolio_assistant/presentation/shared/charts/portfolio_area_line_chart.dart';
import 'package:portfolio_assistant/presentation/shared/loading/skeleton.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/pnl_badge.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/skeleton_text.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';

/// La card del total: valor, variación del período (diciendo de qué
/// período), gráfico y selector de rango. Arrastrando el dedo sobre el
/// gráfico se ve el valor de cada día y la variación desde el inicio del
/// período hasta ese día. Con `summary` en `null`
/// ([PortfolioHeroSection.skeleton]) es su propio skeleton: misma card y
/// alturas, valores en barras.
class PortfolioHeroSection extends StatefulWidget {
  final PortfolioSummary? summary;

  /// Los puntos del período elegido (valor y costo de cada día).
  final List<PortfolioHistoryPoint> history;
  final double periodPnlAbsolute;
  final double periodPnlPercent;
  final ChartTimeRange selectedRange;
  final ValueChanged<ChartTimeRange> onRangeSelected;

  const PortfolioHeroSection({
    super.key,
    required this.summary,
    required this.history,
    required this.periodPnlAbsolute,
    required this.periodPnlPercent,
    required this.selectedRange,
    required this.onRangeSelected,
  });

  const PortfolioHeroSection.skeleton({
    super.key,
    this.selectedRange = ChartTimeRange.m1,
  }) : summary = null,
       history = const [],
       periodPnlAbsolute = 0,
       periodPnlPercent = 0,
       onRangeSelected = _ignoreRange;

  static void _ignoreRange(ChartTimeRange _) {}

  /// Alto del área del gráfico.
  static const chartHeight = 130.0;

  @override
  State<PortfolioHeroSection> createState() => _PortfolioHeroSectionState();
}

class _PortfolioHeroSectionState extends State<PortfolioHeroSection> {
  /// El día que se está recorriendo en el gráfico, o `null`.
  int? _scrubIndex;

  void _onScrub(int? index) {
    if (index == _scrubIndex) return;
    if (index != null) PortyHapticsService.maybeOf(context)?.scrubTick();
    setState(() => _scrubIndex = index);
  }

  @override
  void didUpdateWidget(PortfolioHeroSection old) {
    super.didUpdateWidget(old);
    // Otro rango (u otros datos): el índice ya no apunta al mismo día.
    if (!identical(old.history, widget.history)) _scrubIndex = null;
  }

  @override
  Widget build(BuildContext context) {
    final currency = AppNumberFormat.currency();
    final colors = context.customColors;
    final summary = widget.summary;
    final skeleton = summary == null;
    final badgeStyle = Theme.of(context).textTheme.labelMedium;
    final history = widget.history;
    final chartValues = [for (final p in history) p.totalValue];
    final scrub =
        _scrubIndex != null && _scrubIndex! < history.length
            ? _scrubIndex
            : null;

    // Recorriendo: el valor de ese día y la variación desde el inicio del
    // período hasta él (misma cuenta que la del período: la plata nueva no
    // cuenta como ganancia). Si no, el total de hoy y la del período.
    final double value;
    final double pnl;
    final double pnlPercent;
    final String periodText;
    if (scrub != null) {
      final upTo = HomeChartUtils.periodPnlFromHistory(
        history.sublist(0, scrub + 1),
      );
      value = history[scrub].totalValue;
      pnl = upTo.absolute;
      pnlPercent = upTo.percent;
      periodText = DateFormat.yMMMd().format(history[scrub].date);
    } else {
      value = summary?.totalValue ?? 0;
      pnl = widget.periodPnlAbsolute;
      pnlPercent = widget.periodPnlPercent;
      periodText = widget.selectedRange.periodLabel;
    }
    final sign = pnl >= 0 ? '+' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.pageHorizontal),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.9, -0.7),
            radius: 1.2,
            colors: [
              Color.lerp(colors.surfaceCard, colors.accentWarm, 0.22)!,
              colors.surfaceCard,
            ],
            stops: const [0.0, 0.85],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'portfolio_total_label'.tr(),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Los valores cambian en el lugar con un crossfade corto
                  // (caché → datos nuevos, o al refrescar).
                  SkeletonText(
                    skeleton ? null : currency.format(value),
                    // Recorriendo, el valor sigue al dedo sin crossfade.
                    animate: scrub == null,
                    placeholder: '\$00,000.00',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: colors.textPrimary,
                      fontSize: 40,
                      letterSpacing: -1.5,
                      height: 1.0,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      SkeletonText(
                        skeleton ? null : '$sign${currency.format(pnl)}',
                        animate: scrub == null,
                        placeholder: '+\$000.00',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          color: colors.pnlColor(pnl),
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (skeleton)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: SkeletonText(
                            null,
                            placeholder: '+0.0%',
                            style: badgeStyle,
                          ),
                        )
                      else ...[
                        PnlBadge(percent: pnlPercent),
                        // De qué período es la variación (o qué día se
                        // está recorriendo).
                        Text(
                          periodText,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            if (skeleton)
              const SizedBox(
                height: PortfolioHeroSection.chartHeight,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: SkeletonBlock(radius: 12),
                ),
              )
            else
              PortfolioAreaLineChart(
                key: ValueKey(
                  chartValues.isEmpty
                      ? 'empty'
                      : '${chartValues.length}_${chartValues.last}',
                ),
                values: chartValues,
                showYAxisLabels: false,
                height: PortfolioHeroSection.chartHeight,
                onScrub: chartValues.length < 2 ? null : _onScrub,
                scrubIndex: scrub,
                showStartReference: true,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: SegmentedChoice<ChartTimeRange>(
                selected: widget.selectedRange,
                onChanged: widget.onRangeSelected,
                options: [
                  for (final range in ChartTimeRange.values)
                    (value: range, label: range.label),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
