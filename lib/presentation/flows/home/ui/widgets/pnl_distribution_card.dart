import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/shared/charts/pnl_bar_chart.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/home_chart_card.dart';

class PnlDistributionCard extends StatelessWidget {
  final List<PositionValuation> valuations;

  const PnlDistributionCard({super.key, required this.valuations});

  @override
  Widget build(BuildContext context) {
    final sorted = [...valuations]
      ..sort((a, b) => b.pnlAbsolute.compareTo(a.pnlAbsolute));

    final items = sorted
        .map(
          (v) => PnlBarChartItem(
            label: v.position.ticker,
            value: v.pnlAbsolute,
          ),
        )
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sectionGap,
      ),
      child: HomeChartCard(
        title: 'chart_pnl_distribution'.tr(),
        child: PnlBarChart(items: items),
      ),
    );
  }
}
