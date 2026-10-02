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
import 'package:portfolio_assistant/presentation/shared/widgets/fade_slide_in.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/labeled_value_row.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/section_header.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/skeleton_text.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/surface_card.dart';

class PositionDetailScreen extends StatefulHookConsumerWidget {
  const PositionDetailScreen({super.key, required this.ticker, this.seed});

  final String ticker;

  /// Lo que la home ya sabe de esta posición (ver [PositionDetailSeed]):
  /// con él, el detalle se ve completo desde el primer frame de la
  /// transición. Sin él (deep link), arranca con un skeleton.
  final PositionDetailSeed? seed;

  /// Crossfade skeleton → contenido, y de cada valor que cambia en el lugar
  /// al refrescar.
  static const swapDuration = Duration(milliseconds: 200);

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _PositionDetailScreenState();
}

class _PositionDetailScreenState
    extends BaseStatefulWidget<PositionDetailScreen> {
  late final PositionDetailArgs _args = PositionDetailArgs(
    widget.ticker,
    seed: widget.seed,
  );

  // Con seed el contenido ya está en el primer frame (entra con la ruta);
  // la entrada escalonada de las cards solo se usa al salir del skeleton.
  late final bool _seeded = widget.seed != null;

  @override
  void initState() {
    super.initState();
    // Con seed, el refresh (precio fresco) espera a que termine la
    // transición: los datos ya están en pantalla y así el resultado no
    // reconstruye la lista en medio del push. Sin seed (deep link) arranca
    // ya: el skeleton está en pantalla y cada ms cuenta.
    runAfterPostFrameCallback(() {
      if (!mounted) return;
      final animation = ModalRoute.of(context)?.animation;
      void start() {
        if (mounted) ref.read(positionDetailProvider(_args).notifier).init();
      }

      if (!_seeded || animation == null || animation.isCompleted) {
        start();
      } else {
        void onStatus(AnimationStatus status) {
          if (status != AnimationStatus.completed) return;
          animation.removeStatusListener(onStatus);
          start();
        }

        animation.addStatusListener(onStatus);
      }
    });
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
        .read(positionDetailProvider(_args).notifier)
        .onCloseCompleted(success: result == true);
  }

  @override
  Widget buildView(BuildContext context) {
    final notifier = ref.read(positionDetailProvider(_args).notifier);
    final state = ref.watch(positionDetailProvider(_args));
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    ref.listen(positionDetailProvider(_args), (previous, next) {
      final request = next.closeRequest;
      if (request != null && previous?.closeRequest != request) {
        _handleCloseRequest(request);
      }

      if (next.shouldPop && !(previous?.shouldPop ?? false)) {
        notifier.acknowledgePop();
        context.pop(true);
      }
    });

    final Widget body;
    final String bodyKey;
    if (state.summary != null) {
      bodyKey = 'content';
      body = RefreshIndicator(
        color: context.customColors.accentBlue,
        backgroundColor: context.customColors.surfaceCard,
        onRefresh: notifier.load,
        child: _DetailList(
          summary: state.summary,
          lots: state.lots,
          onCloseAll: notifier.closeAll,
          onCloseLot: notifier.closeLot,
          animateEntrance: !_seeded,
        ),
      );
    } else if (state.errorMessage != null) {
      bodyKey = 'error';
      body = _ErrorBody(message: state.errorMessage!, onRetry: notifier.load);
    } else {
      // Skeleton: la misma lista con los valores vacíos, así tiene la altura
      // final y el cambio a datos no mueve nada.
      bodyKey = 'skeleton';
      body = const _DetailList(summary: null, lots: [null]);
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.ticker)),
      body: AnimatedSwitcher(
        duration:
            reduceMotion ? Duration.zero : PositionDetailScreen.swapDuration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        layoutBuilder:
            (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, if (current != null) current],
            ),
        child: KeyedSubtree(key: ValueKey(bodyKey), child: body),
      ),
    );
  }
}

/// Resumen + botón + compras. Con `summary == null` (o un lote `null`) es
/// su propio skeleton: mismos labels y alturas, valores en barras.
class _DetailList extends StatelessWidget {
  const _DetailList({
    required this.summary,
    required this.lots,
    this.onCloseAll,
    this.onCloseLot,
    this.animateEntrance = false,
  });

  final PositionValuation? summary;
  final List<PositionValuation?> lots;
  final VoidCallback? onCloseAll;
  final void Function(PositionValuation lot)? onCloseLot;
  final bool animateEntrance;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final dateFormat = DateFormat.yMMMd();
    final skeleton = summary == null;
    var order = 0;

    // Misma entrada que las cards de Porty: fade + subida corta,
    // escalonada. Solo al reemplazar el skeleton.
    Widget enter(Widget child) {
      final delay = Duration(milliseconds: 40 * order++);
      if (!animateEntrance) return child;
      return FadeSlideIn(
        delay: delay,
        duration: const Duration(milliseconds: 240),
        child: child,
      );
    }

    return ListView(
      physics:
          skeleton
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        AppDimens.sp16,
        AppDimens.pageHorizontal,
        AppDimens.sp48,
      ),
      children: [
        enter(_SummaryCard(summary: summary, currency: currency)),
        const SizedBox(height: AppDimens.sp16),
        enter(
          PositionPrimaryButton(
            label: 'position_detail_close_all'.tr(),
            onPressed: skeleton ? null : onCloseAll,
          ),
        ),
        const SizedBox(height: AppDimens.sectionGap),
        SectionHeader(title: 'position_detail_purchases'.tr()),
        const SizedBox(height: AppDimens.sp12),
        MotionAwareSize(
          duration: PositionDetailScreen.swapDuration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < lots.length; i++) ...[
                enter(
                  _PurchaseLotCard(
                    key: ValueKey(lots[i]?.position.id ?? 'skeleton_$i'),
                    lot: lots[i],
                    currency: currency,
                    dateFormat: dateFormat,
                    onClose:
                        lots[i] == null || onCloseLot == null
                            ? null
                            : () => onCloseLot!(lots[i]!),
                  ),
                ),
                if (i < lots.length - 1) const SizedBox(height: AppDimens.sp12),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.currency});

  final PositionValuation? summary;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final summary = this.summary;
    final pnl = summary?.pnlAbsolute ?? 0;
    final sign = pnl >= 0 ? '+' : '';

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'position_detail_summary'.tr(),
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppDimens.sp12),
          LabeledValueRow(
            label: 'position_preview_shares'.tr(),
            value: summary?.position.quantity.toStringAsFixed(4),
            animateValue: true,
          ),
          const SizedBox(height: AppDimens.sp8),
          LabeledValueRow(
            label: 'position_preview_current_price'.tr(),
            value:
                summary == null ? null : currency.format(summary.currentPrice),
            animateValue: true,
          ),
          const SizedBox(height: AppDimens.sp8),
          LabeledValueRow(
            label: 'position_preview_market_value'.tr(),
            value:
                summary == null ? null : currency.format(summary.marketValue),
            animateValue: true,
          ),
          const SizedBox(height: AppDimens.sp8),
          LabeledValueRow(
            label: 'position_preview_pnl'.tr(),
            value:
                summary == null
                    ? null
                    : '$sign${currency.format(pnl)} (${summary.pnlPercent.toStringAsFixed(2)}%)',
            valueColor: summary == null ? null : colors.pnlColor(pnl),
            animateValue: true,
          ),
        ],
      ),
    );
  }
}

class _PurchaseLotCard extends StatelessWidget {
  const _PurchaseLotCard({
    super.key,
    required this.lot,
    required this.currency,
    required this.dateFormat,
    required this.onClose,
  });

  final PositionValuation? lot;
  final NumberFormat currency;
  final DateFormat dateFormat;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final lot = this.lot;
    final pnl = lot?.pnlAbsolute ?? 0;
    final sign = pnl >= 0 ? '+' : '';
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);

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
                    lot == null
                        ? null
                        : dateFormat.format(lot.position.purchaseDate),
                    style: titleStyle?.copyWith(color: colors.textPrimary),
                    placeholder: 'Sep 30, 2026',
                  ),
                ),
              ),
              SkeletonText(
                lot == null ? null : '$sign${currency.format(pnl)}',
                animate: true,
                style: titleStyle?.copyWith(
                  color: colors.pnlColor(pnl),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                placeholder: '+\$000.00',
              ),
            ],
          ),
          const SizedBox(height: AppDimens.sp12),
          LabeledValueRow(
            label: 'position_quantity'.tr(),
            value: lot?.position.quantity.toStringAsFixed(4),
          ),
          const SizedBox(height: AppDimens.sp6),
          LabeledValueRow(
            label: 'position_purchase_price'.tr(),
            value:
                lot == null
                    ? null
                    : currency.format(lot.position.purchasePrice),
          ),
          const SizedBox(height: AppDimens.sp6),
          LabeledValueRow(
            label: 'position_preview_market_value'.tr(),
            value: lot == null ? null : currency.format(lot.marketValue),
            animateValue: true,
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
            Icon(Icons.error_outline_rounded, color: colors.loss, size: 48),
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
