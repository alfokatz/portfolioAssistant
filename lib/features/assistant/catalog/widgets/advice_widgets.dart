import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_projection_chart.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/invest_fit_scorer.dart';
import 'package:portfolio_assistant/shared/utils/genui_helpers.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';

/// Widgets del catálogo de inversión y planificación: opciones de
/// inversión, reparto de presupuesto, metas, proyecciones y tips.
///
/// Criterio común: el número que responde la pregunta va grande (monto a
/// invertir, meta, ahorro mensual) y todo lo demás lo acompaña; los montos
/// salen siempre de [QaFormat] y ningún campo opcional ausente deja un
/// hueco o un "null" en pantalla.
abstract final class AdviceWidgets {
  // ---------------------------------------------------------------------
  // Tip
  // ---------------------------------------------------------------------

  static Widget qaTipBanner(CatalogItemContext ctx) {
    final data = _TipBannerData.fromMap(ctx.data as JsonMap);
    if (data.message.isEmpty) return const SizedBox.shrink();
    return _TipBanner(message: data.message, warning: data.tone == 'warning');
  }

  // ---------------------------------------------------------------------
  // Invest
  // ---------------------------------------------------------------------

  static Widget qaInvestOption(CatalogItemContext ctx) {
    final data = _InvestOptionData.fromMap(ctx.data as JsonMap);
    return _InvestOptionCard(data: data);
  }

  static Widget qaBudgetSplit(CatalogItemContext ctx) {
    final data = _BudgetSplitData.fromMap(ctx.data as JsonMap);
    final total = data.totalBudget;
    final items = data.items;
    final tickers = items.map((i) => i.ticker).where((t) => t.isNotEmpty);
    final tickerList = _joinSpanish(tickers.toList());
    final totalLabel = QaFormat.money(total);

    return QaCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const QaSectionLabel('Reparto simulado'),
          const SizedBox(height: 6),
          Text(totalLabel, style: QaText.display),
          const SizedBox(height: 2),
          Text(
            items.isEmpty
                ? 'Sin activos asignados'
                : 'entre ${QaFormat.plural(items.length, 'activo', 'activos')}',
            style: QaText.label,
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: QaSpace.sectionGap),
            QaSegmentedBar(
              height: 12,
              segments: [
                for (var i = 0; i < items.length; i++)
                  QaSegment(value: items[i].pct, color: QaPalette.series(i)),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const QaDivider(indent: 0),
              _BudgetRow(item: items[i], color: QaPalette.series(i)),
            ],
          ],
          QaFollowUpBar(
            items: [
              if (items.length > 1)
                QaFollowUp(
                  'Confirmar',
                  'Confirmo la simulación de $totalLabel en $tickerList',
                  icon: Icons.check_rounded,
                ),
              QaFollowUp(
                '¿Por qué así?',
                '¿Por qué repartiste así los $totalLabel?',
                icon: Icons.help_outline_rounded,
              ),
              QaFollowUp(
                'Más defensivo',
                'Proponeme un reparto más defensivo de $totalLabel',
                icon: Icons.shield_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget qaInvestConfirm(CatalogItemContext ctx) {
    final data = _InvestConfirmData.fromMap(ctx.data as JsonMap);
    final budget = data.budgetUsd > 0 ? QaFormat.money(data.budgetUsd) : null;

    return QaCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const QaCardTitle(
            title: 'Simulación lista',
            subtitle: 'Resumen educativo, sin operaciones reales',
            icon: Icons.receipt_long_outlined,
            trailing: QaTag('Simulada', icon: Icons.science_outlined),
          ),
          const SizedBox(height: QaSpace.sectionGap),
          QaInset(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (budget != null) ...[
                  Text('Presupuesto simulado', style: QaText.label),
                  const SizedBox(height: 4),
                  Text(budget, style: QaText.display),
                ],
                if (data.tickers.isNotEmpty) ...[
                  if (budget != null) const SizedBox(height: QaSpace.gap),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in data.tickers) _TickerChip(ticker: t),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (data.summary.isNotEmpty) ...[
            const SizedBox(height: QaSpace.gap),
            Text(data.summary, style: QaText.body),
          ],
          if (data.disclaimer.isNotEmpty) ...[
            const SizedBox(height: QaSpace.gap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 13,
                    color: QaColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(data.disclaimer, style: QaText.caption)),
              ],
            ),
          ],
          QaFollowUpBar(
            items: [
              if (budget != null)
                QaFollowUp(
                  'Otra alternativa',
                  'Proponeme otra alternativa para invertir $budget',
                  icon: Icons.swap_horiz_rounded,
                ),
              const QaFollowUp(
                '¿Cómo diversifico?',
                '¿Cómo diversifico mi portfolio?',
                icon: Icons.pie_chart_outline_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Plan
  // ---------------------------------------------------------------------

  static Widget qaGoalCard(CatalogItemContext ctx) {
    final data = _GoalCardData.fromMap(ctx.data as JsonMap);
    final current = data.currentAmount;
    final hasProgress = current != null && data.targetAmount > 0;
    final progress =
        hasProgress ? (current / data.targetAmount).clamp(0.0, 1.0) : 0.0;
    final horizon = _horizonLabel(data.monthsRemaining);
    final dateLine = [
      if (data.targetDateLabel.isNotEmpty) data.targetDateLabel,
      if (horizon != null) horizon,
    ].join(' · ');

    return QaCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QaCardTitle(
            title: data.label.isEmpty ? 'Tu meta' : data.label,
            subtitle: 'Meta de ahorro',
            icon: _goalIcon(data.label),
          ),
          const SizedBox(height: QaSpace.sectionGap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Objetivo', style: QaText.label),
                    const SizedBox(height: 4),
                    Text(
                      QaFormat.money(data.targetAmount),
                      style: QaText.display,
                    ),
                    if (dateLine.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(dateLine, style: QaText.caption),
                    ],
                  ],
                ),
              ),
              if (hasProgress) ...[
                const SizedBox(width: QaSpace.gap),
                Semantics(
                  label: 'Progreso ${_progressPct(progress)}',
                  child: QaRing(
                    value: progress,
                    size: 76,
                    stroke: 7,
                    center: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_progressPct(progress), style: QaText.value),
                        Text(
                          'logrado',
                          style: QaText.caption.copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (hasProgress) ...[
            const SizedBox(height: QaSpace.sectionGap),
            QaInset(
              child: QaStatGrid(
                stats: [
                  QaStat(label: 'Hoy tenés', value: QaFormat.money(current)),
                  QaStat(
                    label: 'Te falta',
                    value: QaFormat.money(
                      math.max(0, data.targetAmount - current),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget qaProjectionStrip(CatalogItemContext ctx) {
    final data = _ProjectionStripData.fromMap(ctx.data as JsonMap);
    final required = data.requiredMonthlySavings;
    final contribution = data.monthlyContributionUsed;
    final onTrack = data.onTrack;
    final reached = required != null && required <= 0;

    // Héroe: lo que el usuario vino a preguntar ("¿cuánto ahorro por
    // mes?"). Sin ese dato, el aporte que ya está haciendo.
    final heroValue = required ?? contribution;
    final heroLabel =
        required != null ? 'Ahorro mensual necesario' : 'Tu aporte mensual';

    final secondary =
        <QaStat>[
          if (data.monthsRemaining > 0)
            QaStat(
              label: 'Plazo',
              value: QaFormat.plural(data.monthsRemaining, 'mes', 'meses'),
            ),
          if (required != null && contribution != null && contribution > 0)
            QaStat(
              label: 'Aportás hoy',
              value: '${QaFormat.money(contribution)}/mes',
            ),
          if (data.projectedAmountAtDate != null)
            QaStat(
              label: 'Llegarías a',
              value: QaFormat.money(data.projectedAmountAtDate!),
            ),
        ].take(3).toList();

    final tag =
        reached
            ? QaTag(
              'Meta alcanzada',
              color: QaColors.accentBlue,
              icon: Icons.check_rounded,
            )
            : onTrack == null
            ? null
            : onTrack
            ? QaTag(
              'En camino',
              color: QaColors.profit,
              icon: Icons.check_rounded,
            )
            : QaTag(
              'Falta ritmo',
              color: QaColors.loss,
              icon: Icons.trending_down_rounded,
            );

    return QaCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QaSectionLabel('Para llegar a tiempo', trailing: tag),
          if (heroValue != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(QaFormat.money(heroValue), style: QaText.display),
                const SizedBox(width: 4),
                Text('/ mes', style: QaText.label),
              ],
            ),
            const SizedBox(height: 2),
            Text(heroLabel, style: QaText.label),
          ],
          if (secondary.isNotEmpty) ...[
            const SizedBox(height: QaSpace.gap),
            QaInset(
              child: QaStatGrid(stats: secondary, columns: secondary.length),
            ),
          ],
          const QaFollowUpBar(
            items: [
              QaFollowUp(
                'Ver proyección',
                '¿Cómo va a crecer mi meta?',
                icon: Icons.show_chart_rounded,
              ),
              QaFollowUp(
                'Hitos',
                '¿Cuáles son los hitos de mi meta?',
                icon: Icons.flag_outlined,
              ),
              QaFollowUp(
                'Guardar meta',
                'Guardá esta meta',
                icon: Icons.bookmark_border_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget qaProjectionChart(CatalogItemContext ctx) {
    final data = _ProjectionChartData.fromMap(ctx.data as JsonMap);
    final points =
        data.points
            .map((p) => ProjectionChartPoint(label: p.label, value: p.value))
            .toList();

    return QaCardShell.staged(
      staged:
          (context, active, onFinished) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              QaProjectionChart(
                label: data.label,
                points: points,
                targetAmount: data.targetAmount,
                active: active,
                onFinished: onFinished,
              ),
              const QaFollowUpBar(
                items: [
                  QaFollowUp(
                    'Ahorro mensual',
                    '¿Cuánto tengo que ahorrar por mes para mi meta?',
                    icon: Icons.savings_outlined,
                  ),
                  QaFollowUp(
                    'Hitos',
                    '¿Cuáles son los hitos de mi meta?',
                    icon: Icons.flag_outlined,
                  ),
                ],
              ),
            ],
          ),
    );
  }

  static Widget qaMilestoneList(CatalogItemContext ctx) {
    final data = _MilestoneListData.fromMap(ctx.data as JsonMap);
    final current = data.currentAmount;
    final items = data.items;
    // "Próximo" = el primer hito no alcanzado; solo se sabe si hay monto
    // actual — sin él, todos se muestran como pendientes neutros.
    final nextIndex =
        current == null ? -1 : items.indexWhere((m) => m.amount > current);

    return QaCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QaSectionLabel(data.title.isEmpty ? 'Hitos de la meta' : data.title),
          const SizedBox(height: QaSpace.gap),
          if (items.isEmpty)
            Text('Sin hitos para mostrar', style: QaText.label)
          else
            for (var i = 0; i < items.length; i++)
              _MilestoneRow(
                item: items[i],
                reached: current != null && items[i].amount <= current,
                isNext: i == nextIndex,
                isFirst: i == 0,
                isLast: i == items.length - 1,
              ),
          const QaFollowUpBar(
            items: [
              QaFollowUp(
                'Ver proyección',
                '¿Cómo va a crecer mi meta?',
                icon: Icons.show_chart_rounded,
              ),
              QaFollowUp(
                'Ahorro mensual',
                '¿Cuánto tengo que ahorrar por mes para mi meta?',
                icon: Icons.savings_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  static String _progressPct(double progress) {
    final pct = progress * 100;
    if (pct > 0 && pct < 1) return '<1%';
    return '${pct.floor()}%';
  }

  /// "Faltan 5 años", "Faltan 3 años y 4 meses", "Faltan 7 meses".
  static String? _horizonLabel(int? months) {
    if (months == null || months <= 0) return null;
    final years = months ~/ 12;
    final rest = months % 12;
    if (years == 0) return 'Faltan ${QaFormat.plural(rest, 'mes', 'meses')}';
    final y = QaFormat.plural(years, 'año', 'años');
    if (rest == 0) return 'Faltan $y';
    return 'Faltan $y y ${QaFormat.plural(rest, 'mes', 'meses')}';
  }

  /// Ícono de la meta a partir de su nombre — la meta la nombra el usuario
  /// en lenguaje libre ("Casa", "Viaje a Japón"), así que es una heurística
  /// por palabras clave con un default neutro.
  static IconData _goalIcon(String label) {
    final l = label.toLowerCase();
    bool has(List<String> words) => words.any(l.contains);
    if (has(['casa', 'depto', 'departamento', 'vivienda', 'hogar'])) {
      return Icons.home_outlined;
    }
    if (has(['auto', 'coche', 'carro', 'moto'])) {
      return Icons.directions_car_outlined;
    }
    if (has(['viaje', 'vacacion', 'vacación'])) {
      return Icons.flight_takeoff_rounded;
    }
    if (has(['retiro', 'jubila', 'pensión', 'pension'])) {
      return Icons.beach_access_outlined;
    }
    if (has(['emergencia', 'colchón', 'colchon'])) {
      return Icons.shield_outlined;
    }
    if (has(['estudio', 'universidad', 'educaci', 'master', 'maestría'])) {
      return Icons.school_outlined;
    }
    if (has(['boda', 'casamiento'])) return Icons.favorite_border_rounded;
    return Icons.flag_outlined;
  }

  static String _joinSpanish(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} y ${items.last}';
  }
}

// -------------------------------------------------------------------------
// Tip banner
// -------------------------------------------------------------------------

class _TipBanner extends StatelessWidget {
  const _TipBanner({required this.message, required this.warning});

  final String message;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? QaColors.loss : QaColors.accentBlue;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            warning ? Icons.warning_amber_rounded : Icons.auto_awesome_outlined,
            size: 16,
            color: color,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(message, style: QaText.body),
          ),
        ),
      ],
    );

    // Una advertencia no es un insight de Porty: bloque plano teñido de
    // rojo, sin la firma de glow — que no se confunda con un tip.
    if (warning) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: QaColors.loss.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(QaSpace.insetRadius),
          border: Border.all(color: QaColors.loss.withValues(alpha: 0.25)),
        ),
        child: content,
      );
    }

    // Un tip es exactamente el tipo de insight que lleva la firma visual
    // de Porty: la variante destacada del shell (borde + glow bitono).
    return QaCardShell(
      highlighted: true,
      padding: const EdgeInsets.all(12),
      child: content,
    );
  }
}

// -------------------------------------------------------------------------
// Invest option
// -------------------------------------------------------------------------

class _InvestOptionCard extends StatelessWidget {
  const _InvestOptionCard({required this.data});

  final _InvestOptionData data;

  @override
  Widget build(BuildContext context) {
    final ticker = data.ticker;
    final risk = _riskTag(data.riskLevel);
    final tags = <Widget>[
      if (data.sector.isNotEmpty) QaTag(data.sector),
      if (risk != null) risk,
    ];
    final budget =
        data.budgetUsd != null && data.budgetUsd! > 0
            ? QaFormat.money(data.budgetUsd!)
            : null;

    return QaCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QaTickerHeader(
            ticker: ticker,
            trailing: _FitIndicator(score: data.fitScore),
          ),
          if (data.currentPrice > 0) ...[
            const SizedBox(height: QaSpace.gap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  QaFormat.price(data.currentPrice),
                  style: QaText.displaySm,
                ),
                if (data.weekChangePct != null) ...[
                  const SizedBox(width: 8),
                  QaDeltaChip(value: data.weekChangePct!, dense: true),
                  const SizedBox(width: 4),
                  Text('7 días', style: QaText.caption),
                ],
              ],
            ),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: tags),
          ],
          if (data.thesis.isNotEmpty) ...[
            const SizedBox(height: QaSpace.gap),
            _ExpandableText(text: data.thesis),
          ],
          if (data.pro.isNotEmpty || data.con.isNotEmpty) ...[
            const SizedBox(height: QaSpace.gap),
            _ProsCons(pro: data.pro, con: data.con),
          ],
          if (ticker.isNotEmpty)
            QaFollowUpBar(
              items: [
                QaTickerFollowUps.analysisFor(ticker),
                QaFollowUp(
                  'Gráfico',
                  '¿Cómo viene $ticker?',
                  icon: Icons.show_chart_rounded,
                ),
                if (budget != null)
                  QaFollowUp(
                    'Simular $budget',
                    'Simulá invertir $budget en $ticker',
                    icon: Icons.science_outlined,
                  ),
                QaFollowUp(
                  'Noticias',
                  '¿Qué noticias hay de $ticker?',
                  icon: Icons.article_outlined,
                  feature: PlanFeature.news,
                  ticker: ticker,
                ),
              ],
            ),
        ],
      ),
    );
  }

  static Widget? _riskTag(String level) => switch (level) {
    'defensivo' => const QaTag('Defensivo', icon: Icons.shield_outlined),
    'intermedio' => const QaTag('Riesgo intermedio', icon: Icons.tune_rounded),
    'crecimiento' => const QaTag(
      'Crecimiento',
      icon: Icons.trending_up_rounded,
    ),
    _ => null,
  };
}

/// Encaje 0–100 como anillo + lectura en palabras: el número solo ("Fit
/// 70") no decía nada; el rótulo explica qué significa y el anillo da la
/// proporción de un vistazo. Sin colores de ganancia/pérdida — no es un
/// valor con signo.
class _FitIndicator extends StatelessWidget {
  const _FitIndicator({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final tier = FitTier.of(score);
    final color = switch (tier) {
      FitTier.good => QaColors.accentBlue,
      FitTier.medium => QaColors.accentBlue.withValues(alpha: 0.55),
      FitTier.low => QaColors.textSecondary,
    };
    return Semantics(
      label: 'Encaje con tu portfolio ${score.round()} de 100, ${tier.label}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tier.label,
                style: QaText.caption.copyWith(
                  color:
                      tier == FitTier.low
                          ? QaColors.textSecondary
                          : QaColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text('con tu perfil', style: QaText.caption),
            ],
          ),
          const SizedBox(width: 8),
          QaRing(
            value: score / 100,
            size: 40,
            stroke: 4,
            color: color,
            center: Text(
              '${score.round()}',
              style: QaText.valueSm.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Texto que se corta a [maxLines] con un "Ver más" local solo si de
/// verdad no entra — una tesis corta no muestra un toggle inútil.
class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text});

  final String text;
  static const maxLines = 3;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: QaText.body),
          maxLines: _ExpandableText.maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            MotionAwareSize(
              duration: const Duration(milliseconds: 200),
              child: Text(
                widget.text,
                style: QaText.body,
                maxLines: _expanded ? null : _ExpandableText.maxLines,
                overflow:
                    _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
            ),
            if (overflows)
              QaTappable(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    _expanded ? 'Ver menos' : 'Ver más',
                    style: QaText.label.copyWith(
                      color: QaColors.accentBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A favor / En contra como dos bloques teñidos. Lado a lado solo si hay
/// ancho de sobra (tablet); en un teléfono apilados se leen mejor que dos
/// columnas angostas de 4-5 líneas cada una.
class _ProsCons extends StatelessWidget {
  const _ProsCons({required this.pro, required this.con});

  final String pro;
  final String con;

  @override
  Widget build(BuildContext context) {
    final blocks = [
      if (pro.isNotEmpty)
        _ProConBlock(
          label: 'A favor',
          text: pro,
          icon: Icons.add_rounded,
          color: QaColors.profit,
        ),
      if (con.isNotEmpty)
        _ProConBlock(
          label: 'En contra',
          text: con,
          icon: Icons.remove_rounded,
          color: QaColors.loss,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (blocks.length == 2 && constraints.maxWidth >= 480) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: blocks[0]),
                const SizedBox(width: 8),
                Expanded(child: blocks[1]),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < blocks.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              blocks[i],
            ],
          ],
        );
      },
    );
  }
}

class _ProConBlock extends StatelessWidget {
  const _ProConBlock({
    required this.label,
    required this.text,
    required this.icon,
    required this.color,
  });

  final String label;
  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return QaInset(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: QaText.eyebrow),
                const SizedBox(height: 3),
                Text(text, style: QaText.body.copyWith(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// Budget split / confirm
// -------------------------------------------------------------------------

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.item, required this.color});

  final _BudgetSplitItem item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          // Swatch del segmento: une la fila con su tramo de la barra.
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          QaTickerAvatar(ticker: item.ticker, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.ticker.isEmpty ? '—' : item.ticker,
              style: QaText.bodyStrong,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(QaFormat.money(item.amount), style: QaText.value),
          const SizedBox(width: 10),
          SizedBox(
            width: 40,
            child: Text(
              QaFormat.pct(item.pct, digits: 0),
              style: QaText.label,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
    if (item.ticker.isEmpty) return row;
    return QaTappable(question: '¿Cómo viene ${item.ticker}?', child: row);
  }
}

class _TickerChip extends StatelessWidget {
  const _TickerChip({required this.ticker});

  final String ticker;

  @override
  Widget build(BuildContext context) {
    return QaTappable(
      question: '¿Cómo viene $ticker?',
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
        decoration: BoxDecoration(
          color: QaColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: QaColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            QaTickerAvatar(ticker: ticker, size: 22),
            const SizedBox(width: 6),
            Text(ticker, style: QaText.valueSm),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------
// Milestones
// -------------------------------------------------------------------------

/// Una fila del timeline vertical: punto + tramo de línea hacia el
/// siguiente. Alcanzado = punto lleno con check; próximo = anillo del
/// acento; pendiente = anillo neutro.
class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({
    required this.item,
    required this.reached,
    required this.isNext,
    required this.isFirst,
    required this.isLast,
  });

  final _MilestoneItem item;
  final bool reached;
  final bool isNext;
  final bool isFirst;
  final bool isLast;

  static const _rail = 20.0;

  @override
  Widget build(BuildContext context) {
    final accent = QaColors.accentBlue;
    final lineColor = reached ? accent.withValues(alpha: 0.5) : QaColors.border;

    final dot =
        reached
            ? Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              child: const Icon(
                Icons.check_rounded,
                size: 12,
                color: Colors.white,
              ),
            )
            : Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: QaColors.surfaceCard,
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      isNext
                          ? accent
                          : QaColors.textSecondary.withValues(alpha: 0.4),
                  width: isNext ? 3 : 2,
                ),
              ),
            );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _rail,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: 12,
                  color: isFirst ? Colors.transparent : lineColor,
                ),
                SizedBox(height: 18, child: Center(child: dot)),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : lineColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 36),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item.label,
                                  style: QaText.bodyStrong,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (reached || isNext) ...[
                                const SizedBox(width: 6),
                                QaTag(
                                  reached ? 'Alcanzado' : 'Próximo',
                                  color: accent,
                                ),
                              ],
                            ],
                          ),
                          if (item.dateLabel.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(item.dateLabel, style: QaText.caption),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      QaFormat.money(item.amount),
                      style: QaText.value.copyWith(
                        color:
                            reached
                                ? QaColors.textSecondary
                                : QaColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// Data
// -------------------------------------------------------------------------

double? _optionalDouble(Object? raw) =>
    raw == null ? null : GenUiHelpers.safeDouble(raw, defaultValue: 0);

final class _TipBannerData {
  _TipBannerData({required this.message, required this.tone});

  factory _TipBannerData.fromMap(JsonMap map) {
    return _TipBannerData(
      message: GenUiHelpers.safeString(map['message'], defaultValue: '').trim(),
      tone: GenUiHelpers.safeEnum(map['tone'], const [
        'info',
        'warning',
      ], defaultValue: 'info'),
    );
  }

  final String message;
  final String tone;
}

final class _InvestOptionData {
  _InvestOptionData({
    required this.ticker,
    required this.thesis,
    required this.fitScore,
    required this.pro,
    required this.con,
    required this.currentPrice,
    required this.weekChangePct,
    required this.riskLevel,
    required this.sector,
    required this.budgetUsd,
  });

  factory _InvestOptionData.fromMap(JsonMap map) {
    final week = _optionalDouble(map['weekChangePct']);
    return _InvestOptionData(
      ticker:
          GenUiHelpers.safeString(
            map['ticker'],
            defaultValue: '',
          ).trim().toUpperCase(),
      thesis: GenUiHelpers.safeString(map['thesis'], defaultValue: '').trim(),
      fitScore:
          GenUiHelpers.safeDouble(
            map['fitScore'],
            defaultValue: 0,
          ).clamp(0, 100).toDouble(),
      pro: GenUiHelpers.safeString(map['pro'], defaultValue: '').trim(),
      con: GenUiHelpers.safeString(map['con'], defaultValue: '').trim(),
      currentPrice: GenUiHelpers.safeDouble(
        map['currentPrice'],
        defaultValue: 0,
      ),
      weekChangePct: week != null && week.isFinite ? week : null,
      riskLevel: GenUiHelpers.safeString(map['riskLevel'], defaultValue: ''),
      sector: GenUiHelpers.safeString(map['sector'], defaultValue: '').trim(),
      budgetUsd: _optionalDouble(map['budgetUsd']),
    );
  }

  final String ticker;
  final String thesis;
  final double fitScore;
  final String pro;
  final String con;
  final double currentPrice;
  final double? weekChangePct;
  final String riskLevel;
  final String sector;
  final double? budgetUsd;
}

final class _BudgetSplitItem {
  _BudgetSplitItem({
    required this.ticker,
    required this.amount,
    required this.pct,
  });

  factory _BudgetSplitItem.fromMap(JsonMap map) {
    return _BudgetSplitItem(
      ticker:
          GenUiHelpers.safeString(
            map['ticker'],
            defaultValue: '',
          ).trim().toUpperCase(),
      amount: math.max(
        0,
        GenUiHelpers.safeDouble(map['amount'], defaultValue: 0),
      ),
      pct: math.max(0, GenUiHelpers.safeDouble(map['pct'], defaultValue: 0)),
    );
  }

  final String ticker;
  final double amount;
  final double pct;
}

final class _BudgetSplitData {
  _BudgetSplitData({required this.totalBudget, required this.items});

  factory _BudgetSplitData.fromMap(JsonMap map) {
    final raw =
        GenUiHelpers.safeList(
          map['items'],
          defaultValue: const <_BudgetSplitItem>[],
          mapItem: (item) => _BudgetSplitItem.fromMap(item as JsonMap),
        ).take(4).toList();
    final amountSum = raw.fold<double>(0, (a, i) => a + i.amount);
    var total = GenUiHelpers.safeDouble(map['totalBudget'], defaultValue: 0);
    if (total <= 0) total = amountSum;

    // El modelo a veces manda solo pct o solo amount: se completa el que
    // falta a partir del otro, para que barra, montos y % cuenten lo mismo.
    final items = [
      for (final i in raw)
        _BudgetSplitItem(
          ticker: i.ticker,
          amount: i.amount > 0 ? i.amount : total * i.pct / 100,
          pct:
              i.pct > 0
                  ? i.pct
                  : (total > 0 ? i.amount / total * 100 : 0).toDouble(),
        ),
    ];
    return _BudgetSplitData(totalBudget: total, items: items);
  }

  final double totalBudget;
  final List<_BudgetSplitItem> items;
}

const _defaultInvestDisclaimer =
    'Simulación educativa. No constituye asesoramiento financiero ni '
    'recomendación de inversión.';

final class _InvestConfirmData {
  _InvestConfirmData({
    required this.summary,
    required this.budgetUsd,
    required this.disclaimer,
    required this.tickers,
  });

  factory _InvestConfirmData.fromMap(JsonMap map) {
    final tickersRaw = map['tickers'];
    final tickers =
        tickersRaw is List
            ? GenUiHelpers.safeStringList(tickersRaw)
            : GenUiHelpers.safeString(tickersRaw, defaultValue: '').split(',');

    return _InvestConfirmData(
      summary: GenUiHelpers.safeString(map['summary'], defaultValue: '').trim(),
      budgetUsd: GenUiHelpers.safeDouble(map['budgetUsd'], defaultValue: 0),
      disclaimer:
          GenUiHelpers.safeString(
            map['disclaimer'],
            defaultValue: _defaultInvestDisclaimer,
          ).trim(),
      tickers:
          tickers
              .map((t) => t.trim().toUpperCase())
              .where((t) => t.isNotEmpty)
              .toList(),
    );
  }

  final String summary;
  final double budgetUsd;
  final String disclaimer;
  final List<String> tickers;
}

final class _GoalCardData {
  _GoalCardData({
    required this.label,
    required this.targetAmount,
    required this.targetDateLabel,
    required this.currentAmount,
    required this.monthsRemaining,
  });

  factory _GoalCardData.fromMap(JsonMap map) {
    final current = _optionalDouble(map['currentAmount']);
    final months = _optionalDouble(map['monthsRemaining']);
    return _GoalCardData(
      label: GenUiHelpers.safeString(map['label'], defaultValue: '').trim(),
      targetAmount: math.max(
        0,
        GenUiHelpers.safeDouble(map['targetAmount'], defaultValue: 0),
      ),
      targetDateLabel:
          GenUiHelpers.safeString(
            map['targetDateLabel'],
            defaultValue: '',
          ).trim(),
      currentAmount: current == null || current < 0 ? null : current,
      monthsRemaining: months?.round(),
    );
  }

  final String label;
  final double targetAmount;
  final String targetDateLabel;
  final double? currentAmount;
  final int? monthsRemaining;
}

final class _ProjectionStripData {
  _ProjectionStripData({
    required this.requiredMonthlySavings,
    required this.monthlyContributionUsed,
    required this.monthsRemaining,
    required this.projectedAmountAtDate,
    required this.onTrack,
  });

  factory _ProjectionStripData.fromMap(JsonMap map) {
    final onTrackRaw = map['onTrack'];
    return _ProjectionStripData(
      requiredMonthlySavings: _optionalDouble(map['requiredMonthlySavings']),
      monthlyContributionUsed: _optionalDouble(map['monthlyContributionUsed']),
      monthsRemaining:
          GenUiHelpers.safeDouble(
            map['monthsRemaining'],
            defaultValue: 0,
          ).round(),
      projectedAmountAtDate: _optionalDouble(map['projectedAmountAtDate']),
      onTrack:
          onTrackRaw == null
              ? null
              : GenUiHelpers.safeBool(onTrackRaw, defaultValue: false),
    );
  }

  final double? requiredMonthlySavings;
  final double? monthlyContributionUsed;
  final int monthsRemaining;
  final double? projectedAmountAtDate;
  final bool? onTrack;
}

final class _ProjectionChartPoint {
  _ProjectionChartPoint({required this.label, required this.value});

  factory _ProjectionChartPoint.fromMap(JsonMap map) {
    return _ProjectionChartPoint(
      label: GenUiHelpers.safeString(map['label'], defaultValue: ''),
      value: GenUiHelpers.safeDouble(map['value'], defaultValue: 0),
    );
  }

  final String label;
  final double value;
}

final class _ProjectionChartData {
  _ProjectionChartData({
    required this.label,
    required this.points,
    required this.targetAmount,
  });

  factory _ProjectionChartData.fromMap(JsonMap map) {
    final target = _optionalDouble(map['targetAmount']);
    return _ProjectionChartData(
      label: GenUiHelpers.safeString(map['label'], defaultValue: ''),
      points: GenUiHelpers.safeList(
        map['points'],
        defaultValue: const <_ProjectionChartPoint>[],
        mapItem: (item) => _ProjectionChartPoint.fromMap(item as JsonMap),
      ),
      targetAmount: target != null && target > 0 ? target : null,
    );
  }

  final String label;
  final List<_ProjectionChartPoint> points;
  final double? targetAmount;
}

final class _MilestoneItem {
  _MilestoneItem({
    required this.label,
    required this.amount,
    required this.dateLabel,
  });

  factory _MilestoneItem.fromMap(JsonMap map) {
    return _MilestoneItem(
      label: GenUiHelpers.safeString(map['label'], defaultValue: ''),
      amount: GenUiHelpers.safeDouble(map['amount'], defaultValue: 0),
      dateLabel: GenUiHelpers.safeString(map['dateLabel'], defaultValue: ''),
    );
  }

  final String label;
  final double amount;
  final String dateLabel;
}

final class _MilestoneListData {
  _MilestoneListData({
    required this.title,
    required this.items,
    required this.currentAmount,
  });

  factory _MilestoneListData.fromMap(JsonMap map) {
    final items = GenUiHelpers.safeList(
      map['items'],
      defaultValue: const <_MilestoneItem>[],
      mapItem: (item) => _MilestoneItem.fromMap(item as JsonMap),
    );
    final current = _optionalDouble(map['currentAmount']);
    return _MilestoneListData(
      title: GenUiHelpers.safeString(map['title'], defaultValue: '').trim(),
      items: items.take(4).toList(),
      currentAmount: current == null || current < 0 ? null : current,
    );
  }

  final String title;
  final List<_MilestoneItem> items;
  final double? currentAmount;
}
