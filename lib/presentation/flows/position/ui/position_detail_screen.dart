import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_router.dart';
import 'package:portfolio_assistant/presentation/flows/position/providers/position_detail_provider.dart';
import 'package:portfolio_assistant/presentation/flows/position/states/position_detail_state.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/labeled_value_row.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/section_header.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/surface_card.dart';

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
    final colors = context.customColors;

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

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ticker),
      ),
      body: state.isLoading
          ? Center(
              child: CircularProgressIndicator(color: colors.accentBlue),
            )
          : state.errorMessage != null
              ? _ErrorBody(
                  message: state.errorMessage!,
                  onRetry: notifier.load,
                )
              : RefreshIndicator(
                  color: colors.accentBlue,
                  backgroundColor: colors.surfaceCard,
                  onRefresh: notifier.load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppDimens.pageHorizontal,
                      AppDimens.sp16,
                      AppDimens.pageHorizontal,
                      AppDimens.sp48,
                    ),
                    children: [
                      if (state.summary != null) ...[
                        _SummaryCard(
                          summary: state.summary!,
                          currency: currency,
                        ),
                        const SizedBox(height: AppDimens.sp16),
                        PositionPrimaryButton(
                          label: 'position_detail_close_all'.tr(),
                          onPressed: notifier.closeAll,
                        ),
                        const SizedBox(height: AppDimens.sectionGap),
                        SectionHeader(title: 'position_detail_purchases'.tr()),
                        const SizedBox(height: AppDimens.sp12),
                      ],
                      for (var i = 0; i < state.lots.length; i++) ...[
                        _PurchaseLotCard(
                          lot: state.lots[i],
                          currency: currency,
                          dateFormat: dateFormat,
                          onClose: () => notifier.closeLot(state.lots[i]),
                        ),
                        if (i < state.lots.length - 1)
                          const SizedBox(height: AppDimens.sp12),
                      ],
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
  });

  final PositionValuation summary;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final pnl = summary.pnlAbsolute;
    final sign = pnl >= 0 ? '+' : '';

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'position_detail_summary'.tr(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(height: AppDimens.sp12),
          LabeledValueRow(
            label: 'position_preview_shares'.tr(),
            value: summary.position.quantity.toStringAsFixed(4),
          ),
          const SizedBox(height: AppDimens.sp8),
          LabeledValueRow(
            label: 'position_preview_current_price'.tr(),
            value: currency.format(summary.currentPrice),
          ),
          const SizedBox(height: AppDimens.sp8),
          LabeledValueRow(
            label: 'position_preview_market_value'.tr(),
            value: currency.format(summary.marketValue),
          ),
          const SizedBox(height: AppDimens.sp8),
          LabeledValueRow(
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

class _PurchaseLotCard extends StatelessWidget {
  const _PurchaseLotCard({
    required this.lot,
    required this.currency,
    required this.dateFormat,
    required this.onClose,
  });

  final PositionValuation lot;
  final NumberFormat currency;
  final DateFormat dateFormat;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final pnl = lot.pnlAbsolute;
    final sign = pnl >= 0 ? '+' : '';

    return SurfaceCard(
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
                        color: colors.textPrimary,
                      ),
                ),
              ),
              Text(
                '$sign${currency.format(pnl)}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.pnlColor(pnl),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.sp12),
          LabeledValueRow(
            label: 'position_quantity'.tr(),
            value: lot.position.quantity.toStringAsFixed(4),
          ),
          const SizedBox(height: AppDimens.sp6),
          LabeledValueRow(
            label: 'position_purchase_price'.tr(),
            value: currency.format(lot.position.purchasePrice),
          ),
          const SizedBox(height: AppDimens.sp6),
          LabeledValueRow(
            label: 'position_preview_market_value'.tr(),
            value: currency.format(lot.marketValue),
          ),
          const SizedBox(height: AppDimens.sp16),
          SizedBox(
            width: double.infinity,
            height: AppDimens.touchTarget,
            child: OutlinedButton.icon(
              onPressed: onClose,
              icon: const Icon(Icons.sell_outlined, size: 18),
              label: Text('position_detail_close_lot'.tr()),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.accentBlue,
                side: BorderSide(color: colors.accentBlue),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                ),
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
    final colors = context.customColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.sp32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: colors.loss,
              size: 48,
            ),
            const SizedBox(height: AppDimens.sp16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: AppDimens.sp24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('retry'.tr()),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.accentBlue,
                side: BorderSide(color: colors.border),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
