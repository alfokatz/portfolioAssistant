import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/position_row_widget.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/section_header.dart';

class PositionsSection extends StatelessWidget {
  final List<PositionValuation> valuations;
  final void Function(PositionValuation valuation)? onClosePosition;
  final Future<bool> Function(PositionValuation valuation)? onDeletePosition;
  final String? actionLabel;
  final VoidCallback? onAction;

  const PositionsSection({
    super.key,
    required this.valuations,
    this.onClosePosition,
    this.onDeletePosition,
    this.actionLabel,
    this.onAction,
  });

  Future<bool> _confirmDelete(BuildContext context, String ticker) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('position_delete_title'.tr()),
        content: Text(
          'position_delete_message'.tr(namedArgs: {'ticker': ticker}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text('delete'.tr()),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'positions_my'.tr(),
            actionLabel: actionLabel,
            onAction: onAction,
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: PortfolioColors.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: PortfolioColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: valuations.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'positions_empty'.tr(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: PortfolioColors.textSecondary),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < valuations.length; i++) ...[
                        _PositionDismissibleRow(
                          valuation: valuations[i],
                          onClosePosition: onClosePosition,
                          onDeletePosition: onDeletePosition,
                          confirmDelete: (ticker) =>
                              _confirmDelete(context, ticker),
                        ),
                        if (i < valuations.length - 1)
                          Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: PortfolioColors.border.withValues(
                              alpha: 0.6,
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _PositionDismissibleRow extends StatelessWidget {
  final PositionValuation valuation;
  final void Function(PositionValuation valuation)? onClosePosition;
  final Future<bool> Function(PositionValuation valuation)? onDeletePosition;
  final Future<bool> Function(String ticker) confirmDelete;

  const _PositionDismissibleRow({
    required this.valuation,
    required this.onClosePosition,
    required this.onDeletePosition,
    required this.confirmDelete,
  });

  @override
  Widget build(BuildContext context) {
    final row = PositionRowWidget(
      valuation: valuation,
      onClose: onClosePosition == null
          ? null
          : () => onClosePosition!(valuation),
      onDelete: onDeletePosition == null
          ? null
          : () async {
              final confirmed =
                  await confirmDelete(valuation.position.ticker);
              if (confirmed) {
                await onDeletePosition!(valuation);
              }
            },
    );

    if (onDeletePosition == null) return row;

    return Dismissible(
      key: ValueKey(valuation.position.ticker),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        final confirmed =
            await confirmDelete(valuation.position.ticker);
        if (!confirmed) return false;
        return onDeletePosition!(valuation);
      },
      background: Container(
        color: PortfolioColors.loss.withValues(alpha: 0.85),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(
          Icons.delete_outline,
          color: PortfolioColors.textPrimary,
        ),
      ),
      child: row,
    );
  }
}
