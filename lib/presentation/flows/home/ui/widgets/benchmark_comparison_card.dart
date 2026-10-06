import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/benchmark_point.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/models/chart_time_range.dart';
import 'package:portfolio_assistant/presentation/flows/home/utils/home_chart_utils.dart';
import 'package:portfolio_assistant/presentation/shared/charts/diverging_bar.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/home_chart_card.dart';

/// Tu cartera contra el S&P 500 en el período elegido arriba: una frase que
/// dice quién ganó y por cuánto, y las dos variaciones con barras desde 0
/// (como "Qué movió tu cartera" del informe semanal).
class BenchmarkComparisonCard extends StatelessWidget {
  final double portfolioPercent;
  final List<BenchmarkPoint> benchmarkPoints;

  /// El rango del gráfico de la Home: de ahí salen las dos variaciones.
  final ChartTimeRange range;

  const BenchmarkComparisonCard({
    super.key,
    required this.portfolioPercent,
    required this.benchmarkPoints,
    required this.range,
  });

  /// Diferencias menores a esto se cuentan como "casi igual".
  static const tieThreshold = 0.3;

  @override
  Widget build(BuildContext context) {
    final returns = HomeChartUtils.benchmarkComparisonReturns(
      portfolioPercent: portfolioPercent,
      benchmarkPoints: benchmarkPoints,
    );
    if (returns == null) return const SizedBox.shrink();
    final colors = context.customColors;
    final diff = returns.differencePercent;
    final points = AppNumberFormat.percent(diff.abs(), signed: false)
        .replaceAll('%', '');
    final verdict =
        diff.abs() < tieThreshold
            ? 'home_benchmark_tie'.tr()
            : diff > 0
            ? 'home_benchmark_ahead'.tr(namedArgs: {'points': points})
            : 'home_benchmark_behind'.tr(namedArgs: {'points': points});
    final maxAbs = math.max(
      returns.portfolioPercent.abs(),
      returns.sp500Percent.abs(),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sp16,
      ),
      child: HomeChartCard(
        title: 'home_benchmark_title'.tr(),
        subtitle: rangeLabel(range),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              verdict,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppDimens.sp20),
            _ReturnRow(
              label: 'chart_benchmark_portfolio'.tr(),
              percent: returns.portfolioPercent,
              maxAbs: maxAbs,
              emphasized: true,
            ),
            const SizedBox(height: AppDimens.sp16),
            _ReturnRow(
              label: 'chart_benchmark_sp500'.tr(),
              percent: returns.sp500Percent,
              maxAbs: maxAbs,
            ),
          ],
        ),
      ),
    );
  }

  /// "Último mes", "Desde tu primera compra"…
  static String rangeLabel(ChartTimeRange range) => switch (range) {
    ChartTimeRange.w1 => 'home_range_w1'.tr(),
    ChartTimeRange.m1 => 'home_range_m1'.tr(),
    ChartTimeRange.m3 => 'home_range_m3'.tr(),
    ChartTimeRange.m6 => 'home_range_m6'.tr(),
    ChartTimeRange.y1 => 'home_range_y1'.tr(),
    ChartTimeRange.all => 'home_range_all'.tr(),
  };
}

class _ReturnRow extends StatelessWidget {
  const _ReturnRow({
    required this.label,
    required this.percent,
    required this.maxAbs,
    this.emphasized = false,
  });

  final String label;
  final double percent;
  final double maxAbs;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final value = AppNumberFormat.percent(percent);
    return Semantics(
      label: '$label, $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: tt.bodyMedium?.copyWith(
                    color:
                        emphasized ? colors.textPrimary : colors.textSecondary,
                    fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              Text(
                value,
                style: tt.titleSmall?.copyWith(
                  color: colors.pnlColor(percent),
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.sp8),
          DivergingBar(value: percent, maxAbs: maxAbs),
        ],
      ),
    );
  }
}
