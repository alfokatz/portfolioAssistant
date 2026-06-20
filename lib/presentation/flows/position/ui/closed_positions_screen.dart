import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/providers/closed_positions_provider.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/labeled_value_row.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/surface_card.dart';

class ClosedPositionsScreen extends StatefulHookConsumerWidget {
  const ClosedPositionsScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _ClosedPositionsScreenState();
}

class _ClosedPositionsScreenState
    extends BaseStatefulWidget<ClosedPositionsScreen> {
  @override
  void initState() {
    super.initState();
    runAfterPostFrameCallback(
      () => ref.read(closedPositionsProvider.notifier).load(),
    );
  }

  @override
  Widget buildView(BuildContext context) {
    final state = ref.watch(closedPositionsProvider);
    final notifier = ref.read(closedPositionsProvider.notifier);
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final colors = context.customColors;

    return Scaffold(
      appBar: AppBar(
        title: Text('closed_positions_title'.tr()),
      ),
      body: state.isLoading
          ? Center(
              child: CircularProgressIndicator(color: colors.accentBlue),
            )
          : state.positions.isEmpty
              ? _EmptyState()
              : RefreshIndicator(
                  color: colors.accentBlue,
                  backgroundColor: colors.surfaceCard,
                  onRefresh: notifier.load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppDimens.pageHorizontal,
                      AppDimens.sp16,
                      AppDimens.pageHorizontal,
                      AppDimens.sp48,
                    ),
                    itemCount: state.positions.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppDimens.sp12),
                    itemBuilder: (context, index) {
                      final position = state.positions[index];
                      final pnl = position.pnlAbsolute;
                      final sign = pnl >= 0 ? '+' : '';

                      return SurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    position.ticker,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: colors.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                                Text(
                                  '$sign${currency.format(pnl)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: colors.pnlColor(pnl),
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppDimens.sp4),
                            Text(
                              'closed_positions_realized_pnl'.tr(),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: colors.textSecondary),
                            ),
                            const SizedBox(height: AppDimens.sp2),
                            Text(
                              '${position.pnlPercent >= 0 ? '+' : ''}'
                              '${position.pnlPercent.toStringAsFixed(2)}%',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: colors.pnlColor(pnl),
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                            const SizedBox(height: AppDimens.sp12),
                            LabeledValueRow(
                              label: 'closed_positions_closed_on'.tr(),
                              value: DateFormat.yMMMd().format(position.closeDate),
                              dense: true,
                            ),
                            LabeledValueRow(
                              label: 'position_quantity'.tr(),
                              value: position.quantity.toStringAsFixed(4),
                              dense: true,
                            ),
                            LabeledValueRow(
                              label: 'close_position_price'.tr(),
                              value: currency.format(position.closePrice),
                              dense: true,
                            ),
                            LabeledValueRow(
                              label: 'close_position_preview_cost'.tr(),
                              value: currency.format(position.costBasis),
                              dense: true,
                            ),
                            LabeledValueRow(
                              label: 'close_position_preview_proceeds'.tr(),
                              value: currency.format(position.proceeds),
                              dense: true,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.sp48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                borderRadius: BorderRadius.circular(AppDimens.radiusLg),
              ),
              child: Icon(
                Icons.archive_outlined,
                size: 28,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDimens.sp20),
            Text(
              'closed_positions_empty'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
