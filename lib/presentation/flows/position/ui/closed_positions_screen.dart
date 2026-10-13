import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_source_badge.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_nav.dart';
import 'package:portfolio_assistant/presentation/flows/position/providers/closed_positions_provider.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/loading/loader_timing.dart';
import 'package:portfolio_assistant/presentation/shared/loading/skeleton.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/pnl_badge.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_says.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/skeleton_text.dart';

/// Tus ventas: arriba, Porty hace el balance en una frase (y una barra de
/// lo que pusiste contra lo que recibiste); abajo, las ventas por mes. Sin ventas, Porty explica qué
/// va a aparecer acá y cómo se llega.
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
    // Los logos usan la paleta del kit de Porty.
    QaColors.resolve(Theme.of(context).brightness);
    // La venta más reciente primero.
    final positions = [...state.positions]
      ..sort((a, b) => b.closeDate.compareTo(a.closeDate));

    return Scaffold(
      appBar: AppBar(title: Text('closed_positions_title'.tr())),
      body: LoadingSwitcher(
        loading: state.isLoading,
        placeholder:
            (_) => const SkeletonScope(
              child: _ClosedPositionsList(positions: null),
            ),
        child:
            (_) =>
                positions.isEmpty
                    ? const _EmptyState()
                    : RefreshIndicator(
                      color: colors.accentBlue,
                      backgroundColor: colors.surfaceCard,
                      onRefresh: notifier.load,
                      child: _ClosedPositionsList(positions: positions),
                    ),
      ),
    );
  }
}

/// El balance de Porty + las ventas por mes. Con [positions] en `null` es
/// su propio skeleton (la misma estructura con los valores en barras).
class _ClosedPositionsList extends StatelessWidget {
  const _ClosedPositionsList({required this.positions});

  final List<ClosedPosition>? positions;

  static const skeletonRows = 3;

  @override
  Widget build(BuildContext context) {
    final positions = this.positions;
    final skeleton = positions == null;
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;

    // Las ventas agrupadas por mes, en el orden en que llegan (la más
    // reciente primero).
    final months = <({DateTime month, List<ClosedPosition> sales})>[];
    for (final p in positions ?? const <ClosedPosition>[]) {
      final month = DateTime(p.closeDate.year, p.closeDate.month);
      if (months.isEmpty || months.last.month != month) {
        months.add((month: month, sales: []));
      }
      months.last.sales.add(p);
    }

    Widget monthHeader(String? label) => Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.sp4),
      child: Semantics(
        header: true,
        child: SkeletonText(
          label,
          placeholder: 'Octubre 2026',
          style: tt.labelLarge?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    Widget rows(List<ClosedPosition?> sales) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sales.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 0.5, color: colors.border),
          _SaleRow(position: sales[i]),
        ],
      ],
    );

    return ListView(
      physics:
          skeleton
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        AppDimens.sp12,
        AppDimens.pageHorizontal,
        AppDimens.sp48,
      ),
      children: [
        _PortyVerdict(positions: positions),
        const SizedBox(height: AppDimens.sp24),
        _Ledger(positions: positions),
        const SizedBox(height: AppDimens.sp40),
        if (skeleton) ...[
          monthHeader(null),
          rows(List.filled(skeletonRows, null)),
        ] else
          for (var m = 0; m < months.length; m++) ...[
            if (m > 0) const SizedBox(height: AppDimens.sp28),
            monthHeader(
              toBeginningOfSentenceCase(
                DateFormat.yMMMM().format(months[m].month),
              ),
            ),
            rows(months[m].sales),
          ],
      ],
    );
  }
}

/// Porty hace el balance de todas tus ventas en una frase: cuánto ganaste o
/// perdiste, sobre cuánto pusiste; y, si hay más de una, cuál fue la mejor.
/// Contento si ganaste, apenas triste si perdiste.
class _PortyVerdict extends StatelessWidget {
  const _PortyVerdict({required this.positions});

  final List<ClosedPosition>? positions;

  /// Marca dónde va el monto dentro de la frase traducida.
  static const _slot = '\u0000';

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final ps = positions;
    if (ps == null) {
      final line = PortySays.style(context);
      return PortySays(
        messageKey: 'skeleton',
        message: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonText(
              null,
              placeholder: 'Con 0 ventas ganaste',
              style: line,
            ),
            const SizedBox(height: AppDimens.sp4),
            SkeletonText(null, placeholder: '+\$000.00, un 00%', style: line),
          ],
        ),
      );
    }

    final s = ClosedPositionsSummary.of(ps);
    final sales =
        ps.length == 1
            ? 'closed_positions_sales_one'.tr()
            : 'closed_positions_sales_count'.tr(
              namedArgs: {'count': '${ps.length}'},
            );
    final key =
        s.pnl > 0
            ? 'closed_positions_verdict_gain'
            : s.pnl < 0
            ? 'closed_positions_verdict_loss'
            : 'closed_positions_verdict_even';
    final sentence = key.tr(
      namedArgs: {
        'sales': sales,
        'amount': _slot,
        'pct': AppNumberFormat.percent(s.pct.abs(), signed: false),
      },
    );
    final parts = sentence.split(_slot);
    final amount = TextSpan(
      text: AppNumberFormat.signedMoney(s.pnl),
      style: TextStyle(
        color: colors.pnlColor(s.pnl),
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    final best = s.best;
    return PortySays(
      messageKey: sentence,
      mood: s.pnl < 0 ? PortyAvatarState.concerned : PortyAvatarState.answered,
      message: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: parts.first),
            if (parts.length > 1) ...[amount, TextSpan(text: parts[1])],
          ],
        ),
      ),
      footnote:
          best == null
              ? null
              : Text(
                'closed_positions_verdict_best'.tr(
                  namedArgs: {
                    'ticker': best.ticker,
                    'pct': AppNumberFormat.percent(best.pnlPercent),
                  },
                ),
                style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
    );
  }
}

/// Lo que pusiste contra lo que recibiste, como una sola barra: la parte
/// neutra es lo que pusiste; lo que se sumó (o lo que faltó) va del color
/// del resultado. Dice lo mismo que la frase de Porty, de un vistazo.
class _Ledger extends StatelessWidget {
  const _Ledger({required this.positions});

  final List<ClosedPosition>? positions;

  static const barHeight = 8.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final ps = positions;
    final s = ps == null ? null : ClosedPositionsSummary.of(ps);

    Widget bar() {
      if (s == null) {
        return const SkeletonBlock(height: barHeight, radius: barHeight / 2);
      }
      final top = s.cost > s.proceeds ? s.cost : s.proceeds;
      // Lo que se mantuvo (el mínimo de los dos) y lo que cambió.
      final kept =
          top <= 0 ? 1.0 : (s.cost < s.proceeds ? s.cost : s.proceeds) / top;
      final change = 1 - kept;
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      return ClipRRect(
        borderRadius: BorderRadius.circular(barHeight / 2),
        child: SizedBox(
          height: barHeight,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutQuart,
            builder:
                (context, t, _) => Row(
                  children: [
                    Expanded(
                      flex: (kept * 1000).round(),
                      child: ColoredBox(
                        color: colors.textSecondary.withValues(alpha: 0.45),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    if (change > 0.001) ...[
                      const SizedBox(width: 2),
                      Expanded(
                        flex: (change * 1000).round(),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: t,
                            heightFactor: 1,
                            child: ColoredBox(
                              color:
                                  s.pnl >= 0
                                      ? colors.profit
                                      : colors.loss.withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar(),
        const SizedBox(height: AppDimens.sp12),
        Row(
          children: [
            Expanded(
              child: _Stat(
                label: 'closed_positions_total_cost'.tr(),
                value: s == null ? null : AppNumberFormat.money(s.cost),
              ),
            ),
            Expanded(
              child: _Stat(
                label: 'closed_positions_total_proceeds'.tr(),
                value: s == null ? null : AppNumberFormat.money(s.proceeds),
                alignEnd: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Las cuentas de todas las ventas juntas.
@visibleForTesting
class ClosedPositionsSummary {
  ClosedPositionsSummary._(this.cost, this.proceeds, this.best);

  factory ClosedPositionsSummary.of(List<ClosedPosition> ps) {
    var cost = 0.0;
    var proceeds = 0.0;
    ClosedPosition? best;
    for (final p in ps) {
      cost += p.costBasis;
      proceeds += p.proceeds;
      if (best == null || p.pnlPercent > best.pnlPercent) best = p;
    }
    // "La mejor" solo tiene sentido entre varias, y si ganó.
    final worthNaming = ps.length > 1 && best != null && best.pnlAbsolute > 0;
    return ClosedPositionsSummary._(cost, proceeds, worthNaming ? best : null);
  }

  final double cost;
  final double proceeds;

  /// La venta con mejor rendimiento, si vale la pena nombrarla.
  final ClosedPosition? best;

  double get pnl => proceeds - cost;
  double get pct => cost > 0 ? pnl / cost * 100 : 0.0;
}

/// Una venta: logo, ticker, cuándo y a qué precio; a la derecha, lo que
/// ganó o perdió. Con [position] en `null` es su propio skeleton.
class _SaleRow extends StatelessWidget {
  const _SaleRow({required this.position});

  final ClosedPosition? position;

  static const avatarSize = 40.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final p = position;
    const tabular = [FontFeature.tabularFigures()];
    final pnl = p?.pnlAbsolute ?? 0;

    String? detail;
    String? date;
    // El mes ya está en el encabezado del grupo.
    if (p != null) {
      date = DateFormat.MMMd().format(p.closeDate);
      final shares =
          p.quantity == 1
              ? 'position_shares_one'.tr()
              : 'position_shares'.tr(
                namedArgs: {'count': AppNumberFormat.shares(p.quantity)},
              );
      detail = 'closed_positions_sale_detail'.tr(
        namedArgs: {
          'shares': shares,
          'price': AppNumberFormat.money(p.closePrice),
        },
      );
    }

    final row = Row(
      children: [
        if (p == null)
          const SkeletonBlock(
            width: avatarSize,
            height: avatarSize,
            radius: avatarSize / 2,
          )
        else
          QaTickerAvatar(ticker: p.ticker, size: avatarSize),
        const SizedBox(width: AppDimens.sp12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // La fecha al lado del ticker: la línea de abajo entra en un
              // renglón aun en un iPhone SE.
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  SkeletonText(
                    p?.ticker,
                    placeholder: 'AAPL',
                    style: tt.titleSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  if (p != null && p.source != PositionSource.manual) ...[
                    const SizedBox(width: AppDimens.sp6),
                    const EtoroSourceBadge(),
                  ],
                  if (date != null) ...[
                    const SizedBox(width: AppDimens.sp6),
                    Flexible(
                      child: Text(
                        date,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              SkeletonText(
                detail,
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
              p == null ? null : AppNumberFormat.signedMoney(pnl),
              placeholder: '+\$000.00',
              style: tt.titleSmall?.copyWith(
                color: colors.pnlColor(pnl),
                fontWeight: FontWeight.w700,
                fontSize: 15,
                fontFeatures: tabular,
              ),
            ),
            const SizedBox(height: 2),
            const SizedBox(height: 2),
            if (p == null)
              const SkeletonBlock(width: 44, height: 18, radius: 4)
            else
              PnlBadge(percent: p.pnlPercent, compact: true),
          ],
        ),
      ],
    );
    if (p == null) return Padding(padding: _rowPadding, child: row);
    // Abre el detalle de la venta.
    return Semantics(
      button: true,
      child: InkWell(
        onTap: () => GotoClosedPositionDetail.of(p).navigate(context: context),
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        child: Padding(padding: _rowPadding, child: row),
      ),
    );
  }

  /// Aire vertical de cada fila (las separa un divisor fino): el toque
  /// cubre la fila entera.
  static const _rowPadding = EdgeInsets.symmetric(vertical: 14);
}

/// Sin ventas: Porty cuenta qué va a aparecer acá y cómo se llega.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Align(
      // Un poco arriba del centro: centrado exacto se ve "caído".
      alignment: const Alignment(0, -0.25),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.sp40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ExcludeSemantics(child: PortyAvatar(size: 64)),
            const SizedBox(height: AppDimens.sp20),
            Text(
              'closed_positions_empty'.tr(),
              textAlign: TextAlign.center,
              style: tt.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: AppDimens.sp8),
            Text(
              'closed_positions_empty_body'.tr(),
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(
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

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String? value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
