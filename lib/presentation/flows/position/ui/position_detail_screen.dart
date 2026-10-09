import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_price_chart.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/assistant/services/price_chart_data_loader.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_source_badge.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_sync_note.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_router.dart';
import 'package:portfolio_assistant/presentation/flows/position/providers/position_detail_provider.dart';
import 'package:portfolio_assistant/presentation/flows/position/states/position_detail_state.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_ticker_header.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/loading/skeleton.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/fade_slide_in.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_status_message.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_question_pill.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/skeleton_text.dart';

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

  /// El título grande ya salió de pantalla: la barra muestra el ticker.
  bool _titleInBar = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final inBar = n.metrics.pixels > PositionTickerHeader.height;
    if (inBar != _titleInBar) setState(() => _titleInBar = inBar);
    return false;
  }

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
          ticker: widget.ticker,
          summary: state.summary,
          lots: state.lots,
          onCloseAll: notifier.closeAll,
          onCloseLot: notifier.closeLot,
          onAskPorty:
              (question) => GotoAssistant(
                initialQuestion: question,
              ).navigate(context: context),
          animateEntrance: !_seeded,
        ),
      );
    } else if (state.errorMessage != null) {
      bodyKey = 'error';
      body =
          state.notFound
              // Se vendió o se borró (p. ej. "Ver en cartera" de una venta
              // de Porty que cerró todo): la venta está en las cerradas.
              ? PortyStatusMessage(
                title: 'position_detail_not_found_title'.tr(),
                body: 'position_detail_not_found_body'.tr(),
                actionLabel: 'position_detail_not_found_action'.tr(),
                // Reemplaza este detalle: volver no tiene que traer de
                // nuevo una posición que no existe.
                onAction:
                    () => context.pushReplacementNamed(
                      PositionRouter.closedListRouteName,
                    ),
              )
              : PortyStatusMessage(
                mood: PortyAvatarState.error,
                title: 'position_detail_error_title'.tr(),
                body: 'position_detail_error_body'.tr(),
                actionLabel: 'retry'.tr(),
                onAction: notifier.load,
              );
    } else {
      // Skeleton: la misma lista con los valores vacíos, así tiene la altura
      // final y el cambio a datos no mueve nada.
      bodyKey = 'skeleton';
      body = _DetailList(
        ticker: widget.ticker,
        summary: null,
        lots: const [null],
      );
    }

    // Los logos y el gráfico usan la paleta del kit de Porty.
    QaColors.resolve(Theme.of(context).brightness);
    return Scaffold(
      appBar: AppBar(
        title: AnimatedOpacity(
          opacity: _titleInBar ? 1 : 0,
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 160),
          child: ExcludeSemantics(
            excluding: !_titleInBar,
            child: Text(widget.ticker),
          ),
        ),
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: AnimatedSwitcher(
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
      ),
    );
  }
}

/// El detalle de una posición, de arriba abajo: quién es (logo, ticker,
/// nombre), cuánto vale tu posición y cuánto ganaste, tus compras, el
/// precio de la acción, una pregunta lista para Porty y, al final, cerrar
/// la posición (lo único que no se deshace va último y sin protagonismo).
///
/// Con `summary == null` (o un lote `null`) es su propio skeleton: mismos
/// títulos y alturas, valores en barras.
class _DetailList extends StatelessWidget {
  const _DetailList({
    required this.ticker,
    required this.summary,
    required this.lots,
    this.onCloseAll,
    this.onCloseLot,
    this.onAskPorty,
    this.animateEntrance = false,
  });

  final String ticker;
  final PositionValuation? summary;
  final List<PositionValuation?> lots;
  final VoidCallback? onCloseAll;
  final void Function(PositionValuation lot)? onCloseLot;
  final ValueChanged<String>? onAskPorty;
  final bool animateEntrance;

  @override
  Widget build(BuildContext context) {
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

    // Cerrar una compra suelta solo tiene sentido con más de una: con una
    // sola es lo mismo que cerrar toda la posición (el botón del final).
    final closeLot = lots.length > 1 ? onCloseLot : null;
    // Lo importado de eToro no se cierra ni se edita desde Porty: en lugar
    // del botón de cerrar va la nota de sincronización.
    final imported = [
      for (final lot in lots)
        if (lot != null && lot.position.isReadOnly) lot,
    ];
    final allImported = imported.isNotEmpty && imported.length == lots.length;
    final lastSync = imported
        .map((l) => l.position.syncedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (latest, d) => latest == null || d.isAfter(latest) ? d : latest,
        );
    final question = 'position_detail_porty_question'.tr(
      namedArgs: {'ticker': ticker},
    );

    return ListView(
      physics:
          skeleton
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sp48,
      ),
      children: [
        PositionTickerHeader(ticker: ticker),
        const SizedBox(height: AppDimens.sp24),
        enter(_PositionCard(summary: summary)),
        const SizedBox(height: AppDimens.sp16),
        enter(_PurchasesCard(lots: lots, onCloseLot: closeLot)),
        const SizedBox(height: AppDimens.sp16),
        // Después de lo tuyo, el mercado. Va abajo también porque su alto
        // depende de los datos: arriba movería las compras al cargar.
        enter(_PriceCard(ticker: ticker, skeleton: skeleton)),
        if (!skeleton) ...[
          const SizedBox(height: AppDimens.sp24),
          enter(
            Align(
              alignment: Alignment.centerLeft,
              child: PortyQuestionPill(
                question: question,
                onTap: () => onAskPorty?.call(question),
              ),
            ),
          ),
          const SizedBox(height: AppDimens.sp32),
          if (imported.isNotEmpty) ...[
            enter(EtoroSyncNote(syncedAt: lastSync, partial: !allImported)),
            if (!allImported) const SizedBox(height: AppDimens.sp24),
          ],
          // Con alguna compra importada, "cerrar todo" no aplica: las
          // manuales se cierran de a una desde "Tus compras".
          if (imported.isEmpty) enter(_CloseAllButton(onPressed: onCloseAll)),
        ],
      ],
    );
  }
}

/// Card con título fuerte (como las de Insights) y su contenido.
class _Card extends StatelessWidget {
  const _Card({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(AppDimens.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: tt.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: tt.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: AppDimens.sp16),
          child,
        ],
      ),
    );
  }
}

/// Tu posición: lo que vale hoy (el número protagonista) y lo que ganaste o
/// perdiste desde la compra; abajo, las métricas que lo explican.
class _PositionCard extends StatelessWidget {
  const _PositionCard({required this.summary});

  final PositionValuation? summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final s = summary;
    const tabular = [FontFeature.tabularFigures()];
    final pnl = s?.pnlAbsolute ?? 0;
    final invested = s?.position.costBasis;

    return _Card(
      title: 'position_detail_summary'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonText(
            s == null ? null : AppNumberFormat.money(s.marketValue),
            animate: true,
            placeholder: '\$0,000.00',
            style: tt.displaySmall?.copyWith(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              height: 1.1,
              color: colors.textPrimary,
              fontFeatures: tabular,
            ),
          ),
          const SizedBox(height: AppDimens.sp6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppDimens.sp6,
            children: [
              SkeletonText(
                s == null
                    ? null
                    : '${AppNumberFormat.signedMoney(pnl)} · '
                        '${AppNumberFormat.percent(s.pnlPercent)}',
                animate: true,
                placeholder: '+\$000.00 · +00.0%',
                style: tt.bodyMedium?.copyWith(
                  color: colors.pnlColor(pnl),
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabular,
                ),
              ),
              Text(
                'position_detail_since_purchase'.tr(),
                style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.sp20),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'position_preview_shares'.tr(),
                  value: s == null ? null : AppNumberFormat.shares(s.position.quantity),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'position_preview_current_price'.tr(),
                  value:
                      s == null ? null : AppNumberFormat.money(s.currentPrice),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'position_detail_avg_price'.tr(),
                  value:
                      s == null
                          ? null
                          : AppNumberFormat.money(s.position.purchasePrice),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'position_detail_invested'.tr(),
                  value:
                      invested == null ? null : AppNumberFormat.money(invested),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: tt.bodySmall?.copyWith(color: colors.textSecondary)),
        const SizedBox(height: 2),
        SkeletonText(
          value,
          animate: true,
          placeholder: '\$000.00',
          style: tt.titleSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 15,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// El precio de la acción con el gráfico de Porty (datos reales, rangos y
/// scrub). En el skeleton, un bloque del mismo alto.
class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.ticker, required this.skeleton});

  final String ticker;
  final bool skeleton;

  static const skeletonHeight = 290.0;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'position_detail_price'.tr(),
      child:
          skeleton
              ? const SkeletonBlock(height: skeletonHeight, radius: 12)
              : QaPriceChart(
                ticker: ticker,
                initialRange: PriceChartRange.month,
                // El ticker ya está en el título de la pantalla.
                showHeader: false,
                // Sin datos de precio, la card queda con un aviso corto en
                // vez de un gráfico vacío.
                fallback: Text(
                  'position_detail_price_unavailable'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.customColors.textSecondary,
                  ),
                ),
              ),
    );
  }
}

/// Tus compras: una fila por compra (fecha, cuántas acciones y a cuánto;
/// lo que ganó cada una), separadas solo por espacio.
class _PurchasesCard extends StatelessWidget {
  const _PurchasesCard({required this.lots, required this.onCloseLot});

  final List<PositionValuation?> lots;
  final void Function(PositionValuation lot)? onCloseLot;

  @override
  Widget build(BuildContext context) {
    final skeleton = lots.any((l) => l == null);
    final count = lots.length;
    return _Card(
      title: 'position_detail_purchases'.tr(),
      subtitle:
          skeleton
              ? null
              : count == 1
              ? 'position_detail_purchases_one'.tr()
              : 'position_detail_purchases_count'.tr(
                namedArgs: {'count': '$count'},
              ),
      child: MotionAwareSize(
        duration: PositionDetailScreen.swapDuration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < lots.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _PurchaseRow(
                key: ValueKey(lots[i]?.position.id ?? 'skeleton_$i'),
                lot: lots[i],
                onClose:
                    lots[i] == null ||
                            onCloseLot == null ||
                            lots[i]!.position.isReadOnly
                        ? null
                        : () => onCloseLot!(lots[i]!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({super.key, required this.lot, required this.onClose});

  final PositionValuation? lot;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final lot = this.lot;
    final pnl = lot?.pnlAbsolute ?? 0;
    const tabular = [FontFeature.tabularFigures()];

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: SkeletonText(
                      lot == null
                          ? null
                          : DateFormat.yMMMd().format(lot.position.purchaseDate),
                      placeholder: '30 sept 2026',
                      style: tt.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (lot?.position.isReadOnly ?? false) ...[
                    const SizedBox(width: AppDimens.sp6),
                    const EtoroSourceBadge(),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              SkeletonText(
                lot == null
                    ? null
                    : 'position_detail_lot_detail'.tr(
                      namedArgs: {
                        'shares':
                            lot.position.quantity == 1
                                ? 'position_shares_one'.tr()
                                : 'position_shares'.tr(
                                  namedArgs: {
                                    'count': AppNumberFormat.shares(
                                      lot.position.quantity,
                                    ),
                                  },
                                ),
                        'price': AppNumberFormat.money(
                          lot.position.purchasePrice,
                        ),
                      },
                    ),
                placeholder: '0 acciones a \$000.00',
                style: tt.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppDimens.sp12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SkeletonText(
              lot == null ? null : AppNumberFormat.signedMoney(pnl),
              animate: true,
              placeholder: '+\$000.00',
              style: tt.titleSmall?.copyWith(
                color: colors.pnlColor(pnl),
                fontWeight: FontWeight.w700,
                fontSize: 15,
                fontFeatures: tabular,
              ),
            ),
            const SizedBox(height: 2),
            SkeletonText(
              lot == null ? null : AppNumberFormat.percent(lot.pnlPercent),
              animate: true,
              placeholder: '+00.0%',
              style: tt.bodySmall?.copyWith(
                color: colors.textSecondary,
                fontFeatures: tabular,
              ),
            ),
          ],
        ),
        if (onClose != null) ...[
          const SizedBox(width: AppDimens.sp8),
          TextButton(
            onPressed: onClose,
            style: TextButton.styleFrom(
              foregroundColor: colors.textPrimary,
              minimumSize: const Size(AppDimens.touchTarget, AppDimens.touchTarget),
              padding: const EdgeInsets.symmetric(horizontal: AppDimens.sp8),
              textStyle: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            child: Text('position_detail_close_lot'.tr()),
          ),
        ],
      ],
    );
  }
}

/// Cerrar toda la posición: al final y secundario (borde, sin relleno). Es
/// lo único de la pantalla que no se deshace.
class _CloseAllButton extends StatelessWidget {
  const _CloseAllButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          ),
          textStyle: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        child: Text('position_detail_close_all'.tr()),
      ),
    );
  }
}
