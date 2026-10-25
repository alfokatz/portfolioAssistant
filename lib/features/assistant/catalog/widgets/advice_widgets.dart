import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/invest_fit_scorer.dart';
import 'package:portfolio_assistant/shared/utils/genui_helpers.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/motion_aware_size.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';

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
            // Las filas se agrupan por proximidad, sin líneas: el alto
            // mínimo de cada fila (área tocable) ya les da el aire.
            const SizedBox(height: QaSpace.gap),
            for (var i = 0; i < items.length; i++)
              _BudgetRow(item: items[i], color: QaPalette.series(i)),
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
          // El disclaimer es el pie de la card: su propia sección, con
          // línea y aire, para que no se lea como parte del resumen.
          if (data.disclaimer.isNotEmpty)
            QaSection(
              child: Row(
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
                  Expanded(
                    child: Text(data.disclaimer, style: QaText.caption),
                  ),
                ],
              ),
            ),
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
  // Helpers
  // ---------------------------------------------------------------------

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
          child: Center(
            child:
                warning
                    ? Icon(Icons.warning_amber_rounded, size: 16, color: color)
                    : PortySpark(size: 14, color: color),
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
            const SizedBox(height: QaSpace.sectionGap),
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
                Text(label.toUpperCase(), style: QaText.insetLabel),
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
