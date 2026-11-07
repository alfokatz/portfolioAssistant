import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/allocation/nav/allocation_router.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/allocation_plan_card_data.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';

/// La card del plan de cartera en el chat (`QaAllocationPlan`). El modelo
/// no pasa datos: todo sale del último `get_allocation_plan` (ver
/// [AllocationPlanCardData]). Muestra el plan contra hoy (dos barras y una
/// fila por ticker con su estado) y, si se pidió, el reparto de un aporte.
abstract final class AllocationPlanWidgets {
  static Widget qaAllocationPlan(CatalogItemContext ctx) {
    return Builder(
      builder:
          (context) => ValueListenableBuilder<TurnEvidence>(
            valueListenable: QaEvidenceScope.listenableOf(
              context,
              ctx.surfaceId,
            ),
            builder: (context, evidence, _) {
              final data = AllocationPlanCardData.from(evidence);
              // Sin el resultado de la tool no hay nada real que mostrar (el
              // chequeo de grounding ya rechaza esa respuesta).
              if (data == null) return const SizedBox.shrink();
              return QaCardShell(
                child: _AllocationPlanBody(data: data, ctx: ctx),
              );
            },
          ),
    );
  }
}

class _AllocationPlanBody extends StatelessWidget {
  const _AllocationPlanBody({required this.data, required this.ctx});

  final AllocationPlanCardData data;
  final CatalogItemContext ctx;

  @override
  Widget build(BuildContext context) {
    final inPlan = [
      for (final r in data.rows)
        if (r.targetPct > 0) r.ticker,
    ];
    Color colorOf(String t) {
      final i = inPlan.indexOf(t);
      return i < 0
          ? QaColors.textSecondary.withValues(alpha: 0.3)
          : QaPalette.series(i);
    }

    final off = data.offPlan;
    final shownRows = [
      for (final r in data.rows)
        if (r.targetPct > 0 || r.currentPct > 0) r,
    ];
    final split =
        data.split.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final after = data.weightsAfter;
    final router = GoRouter.maybeOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QaCardTitle(
          title: 'qa_al_title'.tr(),
          icon: Icons.donut_large_rounded,
          subtitle: 'qa_al_margin'.tr(
            namedArgs: {'pts': '${data.thresholdPts.round()}'},
          ),
          trailing:
              !data.hasHoldings
                  ? null
                  : off.isEmpty
                  ? QaTag('qa_al_on_plan'.tr(), color: QaColors.profit)
                  : QaTag(
                    off.length == 1
                        ? 'qa_al_one_off'.tr()
                        : 'qa_al_n_off'.tr(namedArgs: {'count': '${off.length}'}),
                    color: QaColors.accentWarm,
                  ),
        ),
        const SizedBox(height: QaSpace.sectionGap),
        _BarRow(
          label: 'qa_al_plan'.tr(),
          segments: [
            for (final t in inPlan)
              QaSegment(
                value: data.rows.firstWhere((r) => r.ticker == t).targetPct,
                color: colorOf(t),
              ),
          ],
        ),
        if (data.hasHoldings) ...[
          const SizedBox(height: QaSpace.gap),
          _BarRow(
            label: 'qa_al_today'.tr(),
            segments: [
              for (final r in data.rows)
                if (r.currentPct > 0)
                  QaSegment(value: r.currentPct, color: colorOf(r.ticker)),
            ],
          ),
        ],
        const SizedBox(height: QaSpace.sectionGap),
        for (final (i, r) in shownRows.indexed) ...[
          if (i > 0) const SizedBox(height: QaSpace.rowGap),
          _PlanRow(
            row: r,
            color: colorOf(r.ticker),
            threshold: data.thresholdPts,
            hasHoldings: data.hasHoldings,
          ),
        ],
        if (split.isNotEmpty)
          QaSection(
            title: 'qa_al_if_you_add'.tr(
              namedArgs: {'amount': QaFormat.money(data.contributionUsd ?? 0)},
            ),
            trailing: QaTag('qa_al_buys_only'.tr()),
            child: Column(
              children: [
                for (final (i, e) in split.indexed) ...[
                  if (i > 0) const SizedBox(height: QaSpace.rowGap),
                  _SplitRow(
                    ticker: e.key,
                    amount: e.value,
                    after: after[e.key],
                    target:
                        data.rows
                            .where((r) => r.ticker == e.key)
                            .firstOrNull
                            ?.targetPct,
                  ),
                ],
              ],
            ),
          ),
        if (router != null) ...[
          const SizedBox(height: QaSpace.sectionGap),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => router.pushNamed(AllocationRouter.routeName),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text('qa_al_view_edit'.tr()),
              style: TextButton.styleFrom(
                foregroundColor: QaColors.accentBlue,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 40),
              ),
            ),
          ),
        ],
        QaFollowUpBar(
          surfaceId: ctx.surfaceId,
          items: [
            if (split.isEmpty)
              QaFollowUp(
                'qa_al_fu_contribution'.tr(),
                'qa_al_fu_contribution_q'.tr(),
                icon: Icons.calculate_outlined,
              ),
            QaFollowUp(
              'qa_fu_concentration'.tr(),
              'qa_fu_concentration_q'.tr(),
              icon: Icons.pie_chart_outline_rounded,
            ),
          ],
        ),
      ],
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({required this.label, required this.segments});

  final String label;
  final List<QaSegment> segments;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 40, child: Text(label, style: QaText.label)),
        Expanded(child: QaSegmentedBar(segments: segments)),
      ],
    );
  }
}

/// Un ticker: logo, "Plan 30% · Hoy 15%" y su estado.
class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.row,
    required this.color,
    required this.threshold,
    required this.hasHoldings,
  });

  final AllocationCardRow row;
  final Color color;
  final double threshold;
  final bool hasHoldings;

  @override
  Widget build(BuildContext context) {
    final off = hasHoldings && row.driftPts.abs() >= threshold;
    final pts = row.driftPts.abs().round();
    final status =
        !hasHoldings
            ? null
            : row.targetPct == 0
            ? 'qa_al_off_plan'.tr()
            : !off
            ? 'qa_al_on_plan'.tr()
            : row.driftPts > 0
            ? 'qa_al_pts_up'.tr(namedArgs: {'pts': '$pts'})
            : 'qa_al_pts_down'.tr(namedArgs: {'pts': '$pts'});
    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            QaTickerAvatar(ticker: row.ticker, size: 32),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: QaColors.surfaceCard, width: 2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row.ticker, style: QaText.bodyStrong),
              Text(
                hasHoldings
                    ? 'qa_al_plan_today'.tr(
                      namedArgs: {
                        'plan': QaFormat.pct(row.targetPct, digits: 0),
                        'today': QaFormat.pct(row.currentPct, digits: 0),
                      },
                    )
                    : 'qa_al_plan_only'.tr(
                      namedArgs: {'plan': QaFormat.pct(row.targetPct, digits: 0)},
                    ),
                style: QaText.label,
              ),
            ],
          ),
        ),
        if (status != null) ...[
          const SizedBox(width: 8),
          QaTag(
            status,
            // Fuera del plan (objetivo 0) y dentro del margen: ni bien ni
            // mal, gris; pasado del margen, el tono de aviso.
            color:
                off
                    ? QaColors.accentWarm
                    : row.targetPct == 0
                    ? null
                    : QaColors.profit,
          ),
        ],
      ],
    );
  }
}

/// Cuánto va a un ticker del aporte y cómo quedaría.
class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.ticker,
    required this.amount,
    this.after,
    this.target,
  });

  final String ticker;
  final double amount;
  final double? after;
  final double? target;

  @override
  Widget build(BuildContext context) {
    final after = this.after;
    final target = this.target;
    return Row(
      children: [
        QaTickerAvatar(ticker: ticker, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ticker, style: QaText.bodyStrong),
              if (after != null && target != null)
                Text(
                  'qa_al_would_be'.tr(
                    namedArgs: {
                      'after': QaFormat.pct(after, digits: 0),
                      'target': QaFormat.pct(target, digits: 0),
                    },
                  ),
                  style: QaText.label,
                ),
            ],
          ),
        ),
        Text(QaFormat.money(amount), style: QaText.valueSm),
      ],
    );
  }
}
