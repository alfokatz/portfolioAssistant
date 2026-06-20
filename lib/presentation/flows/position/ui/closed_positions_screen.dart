import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/providers/closed_positions_provider.dart';

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
          ? const Center(child: CircularProgressIndicator())
          : state.positions.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(
                      'closed_positions_empty'.tr(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: PortfolioColors.textSecondary,
                          ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: notifier.load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: state.positions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final position = state.positions[index];
                      final pnl = position.pnlAbsolute;
                      final sign = pnl >= 0 ? '+' : '';

                      return Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: PortfolioColors.surfaceCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: PortfolioColors.border),
                        ),
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
                                          color: PortfolioColors.textPrimary,
                                        ),
                                  ),
                                ),
                                Text(
                                  '$sign${currency.format(pnl)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: colors.pnlColor(pnl),
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'closed_positions_realized_pnl'.tr(),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: PortfolioColors.textSecondary,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${position.pnlPercent >= 0 ? '+' : ''}'
                              '${position.pnlPercent.toStringAsFixed(2)}%',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: colors.pnlColor(pnl)),
                            ),
                            const SizedBox(height: 12),
                            _DetailRow(
                              label: 'closed_positions_closed_on'.tr(),
                              value: DateFormat.yMMMd().format(position.closeDate),
                            ),
                            _DetailRow(
                              label: 'position_quantity'.tr(),
                              value: position.quantity.toStringAsFixed(4),
                            ),
                            _DetailRow(
                              label: 'close_position_price'.tr(),
                              value: currency.format(position.closePrice),
                            ),
                            _DetailRow(
                              label: 'close_position_preview_cost'.tr(),
                              value: currency.format(position.costBasis),
                            ),
                            _DetailRow(
                              label: 'close_position_preview_proceeds'.tr(),
                              value: currency.format(position.proceeds),
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

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: PortfolioColors.textSecondary,
              ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PortfolioColors.textSecondary,
                  ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PortfolioColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}
