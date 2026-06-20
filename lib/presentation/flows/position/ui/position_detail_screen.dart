import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_router.dart';
import 'package:portfolio_assistant/presentation/flows/position/providers/position_detail_provider.dart';
import 'package:portfolio_assistant/presentation/flows/position/states/position_detail_state.dart';

class PositionDetailScreen extends StatefulHookConsumerWidget {
  const PositionDetailScreen({super.key, required this.ticker});

  final String ticker;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _PositionDetailScreenState();
}

class _PositionDetailScreenState
    extends BaseStatefulWidget<PositionDetailScreen> {
  @override
  void initState() {
    super.initState();
    runAfterPostFrameCallback(
      () => ref.read(positionDetailProvider(widget.ticker).notifier).init(),
    );
  }

  Future<void> _handleCloseRequest(PositionDetailCloseRequest request) async {
    final result = await context.pushNamed<bool>(
      PositionRouter.closeRouteName,
      extra: {
        'positionId': request.positionId,
        'ticker': request.ticker,
        'quantity': request.quantity,
        'avgPurchasePrice': request.avgPurchasePrice,
      },
    );

    if (!mounted) return;
    await ref
        .read(positionDetailProvider(widget.ticker).notifier)
        .onCloseCompleted(success: result == true);
  }

  @override
  Widget buildView(BuildContext context) {
    final notifier = ref.read(positionDetailProvider(widget.ticker).notifier);
    final state = ref.watch(positionDetailProvider(widget.ticker));

    ref.listen(positionDetailProvider(widget.ticker), (previous, next) {
      final request = next.closeRequest;
      if (request != null && previous?.closeRequest != request) {
        _handleCloseRequest(request);
      }

      if (next.shouldPop && !(previous?.shouldPop ?? false)) {
        notifier.acknowledgePop();
        context.pop(true);
      }
    });

    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final dateFormat = DateFormat.yMMMd();
    final colors = context.customColors;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ticker),
      ),
      body:
          state.isLoading
              ? const Center(
                child: CircularProgressIndicator(
                  color: PortfolioColors.accentBlue,
                ),
              )
              : state.errorMessage != null
              ? _ErrorBody(message: state.errorMessage!, onRetry: notifier.load)
              : RefreshIndicator(
                onRefresh: notifier.load,
                child: ListView(
                  padding: const EdgeInsets.all(AppDimens.mediumMargin),
                  children: [
                    if (state.summary != null) ...[
                      _SummaryCard(
                        summary: state.summary!,
                        currency: currency,
                        colors: colors,
                      ),
                      const SizedBox(height: AppDimens.mediumMargin),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: notifier.closeAll,
                          icon: const Icon(Icons.sell_outlined),
                          label: Text('position_detail_close_all'.tr()),
                          style: FilledButton.styleFrom(
                            backgroundColor: PortfolioColors.accentBlue,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppDimens.largeMargin),
                      Text(
                        'position_detail_purchases'.tr(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: PortfolioColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    for (var i = 0; i < state.lots.length; i++) ...[
                      _PurchaseLotCard(
                        lot: state.lots[i],
                        currency: currency,
                        dateFormat: dateFormat,
                        colors: colors,
                        onClose: () => notifier.closeLot(state.lots[i]),
                      ),
                      if (i < state.lots.length - 1) const SizedBox(height: 12),
                    ],
                    const SizedBox(height: AppDimens.largeMargin),
                  ],
                ),
              ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.summary,
    required this.currency,
    required this.colors,
  });

  final PositionValuation summary;
  final NumberFormat currency;
  final dynamic colors;

  @override
  Widget build(BuildContext context) {
    final pnl = summary.pnlAbsolute;
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
          Text(
            'position_detail_summary'.tr(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: PortfolioColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          _SummaryRow(
            label: 'position_preview_shares'.tr(),
            value: summary.position.quantity.toStringAsFixed(4),
          ),
          const SizedBox(height: 8),
          _SummaryRow(
            label: 'position_preview_current_price'.tr(),
            value: currency.format(summary.currentPrice),
          ),
          const SizedBox(height: 8),
          _SummaryRow(
            label: 'position_preview_market_value'.tr(),
            value: currency.format(summary.marketValue),
          ),
          const SizedBox(height: 8),
          _SummaryRow(
            label: 'position_preview_pnl'.tr(),
            value:
                '$sign${currency.format(pnl)} (${summary.pnlPercent.toStringAsFixed(2)}%)',
            valueColor: colors.pnlColor(pnl),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: PortfolioColors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: valueColor ?? PortfolioColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _PurchaseLotCard extends StatelessWidget {
  const _PurchaseLotCard({
    required this.lot,
    required this.currency,
    required this.dateFormat,
    required this.colors,
    required this.onClose,
  });

  final PositionValuation lot;
  final NumberFormat currency;
  final DateFormat dateFormat;
  final dynamic colors;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final pnl = lot.pnlAbsolute;
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
                  dateFormat.format(lot.position.purchaseDate),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: PortfolioColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '$sign${currency.format(pnl)}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.pnlColor(pnl),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SummaryRow(
            label: 'position_quantity'.tr(),
            value: lot.position.quantity.toStringAsFixed(4),
          ),
          const SizedBox(height: 6),
          _SummaryRow(
            label: 'position_purchase_price'.tr(),
            value: currency.format(lot.position.purchasePrice),
          ),
          const SizedBox(height: 6),
          _SummaryRow(
            label: 'position_preview_market_value'.tr(),
            value: currency.format(lot.marketValue),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onClose,
              icon: const Icon(Icons.sell_outlined, size: 18),
              label: Text('position_detail_close_lot'.tr()),
              style: OutlinedButton.styleFrom(
                foregroundColor: PortfolioColors.accentBlue,
                side: const BorderSide(color: PortfolioColors.accentBlue),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: PortfolioColors.loss,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: PortfolioColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text('retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
