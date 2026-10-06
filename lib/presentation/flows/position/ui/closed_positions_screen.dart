import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/providers/closed_positions_provider.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';
import 'package:portfolio_assistant/presentation/shared/loading/skeleton.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/labeled_value_row.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/skeleton_text.dart';
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
    final colors = context.customColors;

    return Scaffold(
      appBar: AppBar(
        title: Text('closed_positions_title'.tr()),
      ),
      body: LoadingSwitcher(
        loading: state.isLoading,
        placeholder: (_) => const _ClosedPositionsSkeleton(),
        child: (_) => state.positions.isEmpty
              ? _EmptyState()
              : RefreshIndicator(
                  color: colors.accentBlue,
                  backgroundColor: colors.surfaceCard,
                  onRefresh: notifier.load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: _ClosedPositionCard.listPadding,
                    itemCount: state.positions.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppDimens.sp12),
                    itemBuilder: (context, index) {
                      return _ClosedPositionCard(
                        position: state.positions[index],
                      );
                    },
                  ),
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

/// Lo que se ve mientras cargan: las mismas tarjetas con los valores en
/// barras (mismos labels y alturas que con datos).
class _ClosedPositionsSkeleton extends StatelessWidget {
  const _ClosedPositionsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonScope(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: _ClosedPositionCard.listPadding,
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(height: AppDimens.sp12),
        itemBuilder: (_, __) => const _ClosedPositionCard(position: null),
      ),
    );
  }
}

/// Una posición cerrada. Con [position] en `null` es su propio skeleton.
class _ClosedPositionCard extends StatelessWidget {
  const _ClosedPositionCard({required this.position});

  final ClosedPosition? position;

  static const listPadding = EdgeInsets.fromLTRB(
    AppDimens.pageHorizontal,
    AppDimens.sp16,
    AppDimens.pageHorizontal,
    AppDimens.sp48,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final textTheme = Theme.of(context).textTheme;
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final p = position;
    final pnl = p?.pnlAbsolute ?? 0;
    final sign = pnl >= 0 ? '+' : '';

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SkeletonText(
                    p?.ticker,
                    placeholder: 'AAPL',
                    style: textTheme.titleMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SkeletonText(
                p == null ? null : '$sign${currency.format(pnl)}',
                placeholder: '+\$000.00',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.pnlColor(pnl),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.sp4),
          Text(
            'closed_positions_realized_pnl'.tr(),
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppDimens.sp2),
          SkeletonText(
            p == null
                ? null
                : '${p.pnlPercent >= 0 ? '+' : ''}'
                    '${p.pnlPercent.toStringAsFixed(2)}%',
            placeholder: '+00.00%',
            style: textTheme.bodySmall?.copyWith(
              color: colors.pnlColor(pnl),
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: AppDimens.sp12),
          LabeledValueRow(
            label: 'closed_positions_closed_on'.tr(),
            value: p == null ? null : DateFormat.yMMMd().format(p.closeDate),
            dense: true,
          ),
          LabeledValueRow(
            label: 'position_quantity'.tr(),
            value: p?.quantity.toStringAsFixed(4),
            dense: true,
          ),
          LabeledValueRow(
            label: 'close_position_price'.tr(),
            value: p == null ? null : currency.format(p.closePrice),
            dense: true,
          ),
          LabeledValueRow(
            label: 'close_position_preview_cost'.tr(),
            value: p == null ? null : currency.format(p.costBasis),
            dense: true,
          ),
          LabeledValueRow(
            label: 'close_position_preview_proceeds'.tr(),
            value: p == null ? null : currency.format(p.proceeds),
            dense: true,
          ),
        ],
      ),
    );
  }
}
