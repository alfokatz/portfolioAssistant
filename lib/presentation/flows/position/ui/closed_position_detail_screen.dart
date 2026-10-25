import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_router.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_source_badge.dart';
import 'package:portfolio_assistant/presentation/flows/position/providers/closed_position_detail_provider.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_ticker_header.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_question_pill.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_status_message.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/skeleton_text.dart';

/// El detalle de una venta: cuánto ganaste o perdiste, qué vendiste y a
/// cuánto, y una pregunta lista para Porty. Se abre desde la lista de
/// posiciones cerradas y desde "Ver posición cerrada" de una venta que
/// registró Porty.
class ClosedPositionDetailScreen extends ConsumerStatefulWidget {
  const ClosedPositionDetailScreen({
    super.key,
    required this.id,
    required this.ticker,
    this.seed,
  });

  final String id;
  final String ticker;

  /// La venta ya cargada por la pantalla de origen: con ella el detalle se
  /// ve completo desde el primer frame. Sin ella, la busca por [id].
  final ClosedPosition? seed;

  static const swapDuration = Duration(milliseconds: 200);

  @override
  ConsumerState<ClosedPositionDetailScreen> createState() =>
      _ClosedPositionDetailScreenState();
}

class _ClosedPositionDetailScreenState
    extends ConsumerState<ClosedPositionDetailScreen> {
  /// El título grande ya salió de pantalla: la barra muestra el ticker.
  bool _titleInBar = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final inBar = n.metrics.pixels > PositionTickerHeader.height;
    if (inBar != _titleInBar) setState(() => _titleInBar = inBar);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final seed = widget.seed;

    final Widget body;
    final String bodyKey;
    if (seed != null) {
      bodyKey = 'content';
      body = _DetailList(ticker: widget.ticker, sale: seed);
    } else {
      final async = ref.watch(closedPositionDetailProvider(widget.id));
      switch (async) {
        case AsyncData(value: final sale?):
          bodyKey = 'content';
          body = _DetailList(ticker: widget.ticker, sale: sale);
        case AsyncData():
          bodyKey = 'not_found';
          body = PortyStatusMessage(
            title: 'closed_position_detail_not_found_title'.tr(),
            body: 'closed_position_detail_not_found_body'.tr(),
            actionLabel: 'position_detail_not_found_action'.tr(),
            onAction:
                () => context.pushReplacementNamed(
                  PositionRouter.closedListRouteName,
                ),
          );
        case AsyncError():
          bodyKey = 'error';
          body = PortyStatusMessage(
            mood: PortyAvatarState.error,
            title: 'closed_position_detail_error_title'.tr(),
            body: 'position_detail_error_body'.tr(),
            actionLabel: 'retry'.tr(),
            onAction:
                () => ref.invalidate(closedPositionDetailProvider(widget.id)),
          );
        default:
          // Skeleton: la misma lista con los valores vacíos.
          bodyKey = 'skeleton';
          body = _DetailList(ticker: widget.ticker, sale: null);
      }
    }

    // Los logos usan la paleta del kit de Porty.
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
              reduceMotion
                  ? Duration.zero
                  : ClosedPositionDetailScreen.swapDuration,
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

/// De arriba abajo: quién es, cuánto ganaste o perdiste con la venta, qué
/// vendiste y a cuánto, y una pregunta para Porty. Con `sale == null` es
/// su propio skeleton.
class _DetailList extends StatelessWidget {
  const _DetailList({required this.ticker, required this.sale});

  final String ticker;
  final ClosedPosition? sale;

  @override
  Widget build(BuildContext context) {
    final skeleton = sale == null;
    final question = 'closed_position_detail_porty_question'.tr(
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
        _ResultCard(sale: sale),
        const SizedBox(height: AppDimens.sp16),
        _SaleCard(sale: sale),
        if (!skeleton) ...[
          const SizedBox(height: AppDimens.sp24),
          Align(
            alignment: Alignment.centerLeft,
            child: PortyQuestionPill(
              question: question,
              onTap:
                  () => GotoAssistant(
                    initialQuestion: question,
                  ).navigate(context: context),
            ),
          ),
        ],
      ],
    );
  }
}

/// Lo que dejó la venta: la ganancia o pérdida (el número protagonista),
/// el porcentaje sobre lo que pagaste, y lo pagado contra lo recibido.
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.sale});

  final ClosedPosition? sale;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final s = sale;
    const tabular = [FontFeature.tabularFigures()];
    final pnl = s?.pnlAbsolute ?? 0;

    return _Card(
      title: 'closed_position_detail_result'.tr(),
      subtitle:
          s == null
              ? null
              : 'closed_position_detail_sold_on'.tr(
                namedArgs: {'date': DateFormat.yMMMd().format(s.closeDate)},
              ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonText(
            s == null ? null : AppNumberFormat.signedMoney(pnl),
            placeholder: '+\$000.00',
            style: tt.displaySmall?.copyWith(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              height: 1.1,
              color: s == null ? colors.textPrimary : colors.pnlColor(pnl),
              fontFeatures: tabular,
            ),
          ),
          const SizedBox(height: AppDimens.sp6),
          SkeletonText(
            s == null
                ? null
                : 'closed_positions_realized_detail'.tr(
                  namedArgs: {'pct': AppNumberFormat.percent(s.pnlPercent)},
                ),
            placeholder: '+00.0% sobre lo que pagaste',
            style: tt.bodyMedium?.copyWith(
              color: colors.textSecondary,
              fontFeatures: tabular,
            ),
          ),
          // Venta importada: el resultado es el neto que informó eToro
          // (comisiones y dividendos incluidos), no precio × cantidad.
          if (s?.hasBrokerPnl ?? false) ...[
            const SizedBox(height: AppDimens.sp8),
            Row(
              children: [
                const EtoroSourceBadge(),
                const SizedBox(width: AppDimens.sp8),
                Expanded(
                  child: Text(
                    'closed_position_broker_pnl_note'.tr(),
                    style: tt.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppDimens.sp20),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'closed_positions_total_cost'.tr(),
                  value: s == null ? null : AppNumberFormat.money(s.costBasis),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'closed_positions_total_proceeds'.tr(),
                  value: s == null ? null : AppNumberFormat.money(s.proceeds),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Qué se vendió: cuántas acciones, cuándo, a cuánto las habías comprado
/// (promedio) y a cuánto las vendiste.
class _SaleCard extends StatelessWidget {
  const _SaleCard({required this.sale});

  final ClosedPosition? sale;

  @override
  Widget build(BuildContext context) {
    final s = sale;
    return _Card(
      title: 'closed_position_detail_sale'.tr(),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'position_preview_shares'.tr(),
                  value: s == null ? null : AppNumberFormat.shares(s.quantity),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'closed_position_detail_date'.tr(),
                  value:
                      s == null ? null : DateFormat.yMMMd().format(s.closeDate),
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
                          : AppNumberFormat.money(s.avgPurchasePrice),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'closed_position_detail_sale_price'.tr(),
                  value: s == null ? null : AppNumberFormat.money(s.closePrice),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Card con título fuerte, como las del detalle de una posición abierta.
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
