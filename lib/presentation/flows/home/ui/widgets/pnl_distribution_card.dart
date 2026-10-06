import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/charts/diverging_bar.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/home_chart_card.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';

/// P&L de cada posición, de la que más gana a la que más pierde: filas con
/// el número escrito y una barra con el centro en 0 (como "Qué movió tu
/// cartera" del informe semanal). Sin tooltips: todo se lee sin tocar.
class PnlDistributionCard extends StatefulWidget {
  final List<PositionValuation> valuations;

  const PnlDistributionCard({super.key, required this.valuations});

  /// Con más posiciones que esto, se muestran las primeras [collapsedCount]
  /// y un "Ver todas".
  static const compactLimit = 6;
  static const collapsedCount = 5;

  @override
  State<PnlDistributionCard> createState() => _PnlDistributionCardState();
}

class _PnlDistributionCardState extends State<PnlDistributionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.valuations.isEmpty) return const SizedBox.shrink();
    final sorted = [...widget.valuations]
      ..sort((a, b) => b.pnlAbsolute.compareTo(a.pnlAbsolute));
    final maxAbs = sorted.map((v) => v.pnlAbsolute.abs()).fold(0.0, math.max);
    final collapsible = sorted.length > PnlDistributionCard.compactLimit;
    final visible =
        collapsible && !_expanded
            ? sorted.take(PnlDistributionCard.collapsedCount).toList()
            : sorted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sectionGap,
      ),
      child: HomeChartCard(
        title: 'chart_pnl_by_asset'.tr(),
        child: MotionAwareSize(
          duration: const Duration(milliseconds: 220),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                if (i > 0) const SizedBox(height: AppDimens.sp16),
                _PnlRow(valuation: visible[i], maxAbs: maxAbs),
              ],
              if (collapsible)
                _ToggleButton(
                  expanded: _expanded,
                  total: sorted.length,
                  onTap: () => setState(() => _expanded = !_expanded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PnlRow extends StatelessWidget {
  const _PnlRow({required this.valuation, required this.maxAbs});

  final PositionValuation valuation;
  final double maxAbs;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final v = valuation;
    final money = AppNumberFormat.signedMoney(v.pnlAbsolute);
    final percent = AppNumberFormat.percent(v.pnlPercent);
    const tabular = [FontFeature.tabularFigures()];

    return Semantics(
      label: '${v.position.ticker}, $money, $percent',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              QaTickerAvatar(ticker: v.position.ticker, size: 28),
              const SizedBox(width: AppDimens.sp12),
              Expanded(
                child: Text(
                  v.position.ticker,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppDimens.sp8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money,
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.pnlColor(v.pnlAbsolute),
                      fontFeatures: tabular,
                    ),
                  ),
                  Text(
                    percent,
                    style: tt.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      fontFeatures: tabular,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppDimens.sp8),
          DivergingBar(value: v.pnlAbsolute, maxAbs: maxAbs),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.expanded,
    required this.total,
    required this.onTap,
  });

  final bool expanded;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final label =
        expanded
            ? 'home_pnl_show_less'.tr()
            : 'home_pnl_show_all'.tr(args: ['$total']);
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.sp8),
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppDimens.touchTarget,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: tt.labelLarge?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AppDimens.sp4),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: AppDimens.iconMd,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
