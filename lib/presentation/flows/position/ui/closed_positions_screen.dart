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
import 'package:portfolio_assistant/presentation/shared/widgets/skeleton_text.dart';

/// Tus ventas: arriba, el resultado de todas juntas (el número
/// protagonista); abajo, una fila por venta. Sin ventas, Porty explica qué
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
        placeholder: (_) => const SkeletonScope(
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

/// Resumen + ventas. Con [positions] en `null` es su propio skeleton (las
/// mismas cards con los valores en barras).
class _ClosedPositionsList extends StatelessWidget {
  const _ClosedPositionsList({required this.positions});

  final List<ClosedPosition>? positions;

  static const skeletonRows = 3;

  @override
  Widget build(BuildContext context) {
    final positions = this.positions;
    final skeleton = positions == null;
    return ListView(
      physics:
          skeleton
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        AppDimens.sp8,
        AppDimens.pageHorizontal,
        AppDimens.sp48,
      ),
      children: [
        _SummaryCard(positions: positions),
        const SizedBox(height: AppDimens.sp16),
        _Card(
          title: 'closed_positions_sales'.tr(),
          subtitle:
              skeleton
                  ? null
                  : positions.length == 1
                  ? 'closed_positions_sales_one'.tr()
                  : 'closed_positions_sales_count'.tr(
                    namedArgs: {'count': '${positions.length}'},
                  ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < (positions?.length ?? skeletonRows); i++) ...[
                if (i > 0) const SizedBox(height: 6),
                _SaleRow(position: positions?[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// El resultado de todas tus ventas juntas: lo que ganaste o perdiste, sobre
/// cuánto, y lo que pusiste y recibiste.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.positions});

  final List<ClosedPosition>? positions;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final ps = positions;
    const tabular = [FontFeature.tabularFigures()];
    double sum(double Function(ClosedPosition) f) =>
        ps == null ? 0 : ps.fold(0, (acc, p) => acc + f(p));
    final cost = sum((p) => p.costBasis);
    final proceeds = sum((p) => p.proceeds);
    final pnl = proceeds - cost;
    final pct = cost > 0 ? pnl / cost * 100 : 0.0;

    return _Card(
      title: 'closed_positions_realized_pnl'.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonText(
            ps == null ? null : AppNumberFormat.signedMoney(pnl),
            placeholder: '+\$000.00',
            style: tt.displaySmall?.copyWith(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              height: 1.1,
              color: colors.pnlColor(pnl),
              fontFeatures: tabular,
            ),
          ),
          const SizedBox(height: AppDimens.sp6),
          SkeletonText(
            ps == null
                ? null
                : 'closed_positions_realized_detail'.tr(
                  namedArgs: {'pct': AppNumberFormat.percent(pct)},
                ),
            placeholder: '+00.0% sobre lo que pagaste',
            style: tt.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppDimens.sp20),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'closed_positions_total_cost'.tr(),
                  value: ps == null ? null : AppNumberFormat.money(cost),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'closed_positions_total_proceeds'.tr(),
                  value: ps == null ? null : AppNumberFormat.money(proceeds),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Una venta: logo, ticker, cuándo y a qué precio; a la derecha, lo que
/// ganó o perdió. Con [position] en `null` es su propio skeleton.
class _SaleRow extends StatelessWidget {
  const _SaleRow({required this.position});

  final ClosedPosition? position;

  static const avatarSize = 36.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final p = position;
    const tabular = [FontFeature.tabularFigures()];
    final pnl = p?.pnlAbsolute ?? 0;

    String? detail;
    String? date;
    if (p != null) {
      date = DateFormat.yMMMd().format(p.closeDate);
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
            SkeletonText(
              p == null ? null : AppNumberFormat.percent(p.pnlPercent),
              placeholder: '+00.0%',
              style: tt.bodySmall?.copyWith(
                color: colors.textSecondary,
                fontFeatures: tabular,
              ),
            ),
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

  /// Aire vertical de cada fila: con él, el toque cubre la fila entera y
  /// las filas quedan a 14 de distancia (6 entre filas + 4 + 4).
  static const _rowPadding = EdgeInsets.symmetric(vertical: 4);
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

/// Card con título fuerte, como las del resto de la app.
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
