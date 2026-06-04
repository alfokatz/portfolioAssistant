import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/benchmark_point.dart';
import 'package:portfolio_assistant/presentation/shared/charts/benchmark_dual_line_chart.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/home_chart_card.dart';

class BenchmarkComparisonCard extends StatelessWidget {
  final List<BenchmarkPoint> points;

  const BenchmarkComparisonCard({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final portfolio = points.map((p) => p.portfolioNormalized).toList();
    final sp500 = points.map((p) => p.sp500Normalized).toList();

    return HomeChartCard(
      title: 'chart_benchmark_title'.tr(),
      trailing: const BenchmarkLegend(),
      child: BenchmarkDualLineChart(
        portfolioValues: portfolio,
        sp500Values: sp500,
      ),
    );
  }
}
