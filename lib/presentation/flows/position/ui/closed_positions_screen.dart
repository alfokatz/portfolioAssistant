import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

class ClosedPositionsScreen extends StatefulHookConsumerWidget {
  const ClosedPositionsScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _ClosedPositionsScreenState();
}

class _ClosedPositionsScreenState
    extends BaseStatefulWidget<ClosedPositionsScreen> {
  List<ClosedPosition> _positions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    runAfterPostFrameCallback(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await ref.read(getClosedPositionsUseCaseProvider).call();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _positions = result.fold((_) => [], (list) => list);
    });
  }

  @override
  Widget buildView(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final colors = context.customColors;

    return Scaffold(
      backgroundColor: PortfolioColors.background,
      appBar: AppBar(
        title: Text('closed_positions_title'.tr()),
        backgroundColor: PortfolioColors.background,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _positions.isEmpty
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
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: _positions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final position = _positions[index];
                      final pnl = position.pnlAbsolute;
                      final sign = pnl >= 0 ? '+' : '';

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: PortfolioColors.surfaceCard,
                          borderRadius: BorderRadius.circular(16),
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
                                          fontWeight: FontWeight.w700,
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
                                        fontWeight: FontWeight.w700,
                                        color: colors.pnlColor(pnl),
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
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
                ),
          ),
        ],
      ),
    );
  }
}
