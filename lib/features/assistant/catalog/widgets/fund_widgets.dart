import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_evidence_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/assistant/data/market/etf_holdings_data.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';

/// Widgets del catálogo sobre fondos: qué tiene adentro un ETF.
///
/// Como el análisis de empresa, el modelo solo nombra el ticker: cada
/// nombre y peso de la card sale del resultado de `get_etf_holdings`
/// ([QaEvidenceScope]), así ninguna posición puede ser inventada.
abstract final class FundWidgets {
  static Widget qaEtfHoldings(CatalogItemContext ctx) {
    final map = ctx.data as JsonMap;
    final ticker = '${map['ticker'] ?? ''}'.trim().toUpperCase();
    return Builder(
      builder:
          (context) => ValueListenableBuilder<TurnEvidence>(
            valueListenable: QaEvidenceScope.listenableOf(
              context,
              ctx.surfaceId,
            ),
            builder: (context, evidence, _) {
              final data = EtfHoldingsData.from(evidence, ticker);
              // Sin datos de la tool no hay nada real que mostrar (el
              // chequeo de grounding ya rechaza esa respuesta).
              if (data == null || data.isEmpty) return const SizedBox.shrink();
              return QaCardShell(child: _EtfHoldingsBody(data: data));
            },
          ),
    );
  }
}

class _EtfHoldingsBody extends StatelessWidget {
  const _EtfHoldingsBody({required this.data});

  final EtfHoldingsData data;

  static const _shownHoldings = 10;

  @override
  Widget build(BuildContext context) {
    final holdings = data.holdings.take(_shownHoldings).toList();
    final maxWeight = holdings.fold<double>(
      0,
      (a, h) => (h.weightPct ?? 0) > a ? h.weightPct! : a,
    );
    final stats = [
      if (data.expenseRatioPct != null)
        QaStat(
          label: 'Costo anual',
          value: QaFormat.pct(data.expenseRatioPct!, digits: 2),
        ),
      if (data.totalAssetsUsd != null)
        QaStat(
          label: 'Patrimonio',
          value: QaFormat.moneyCompact(data.totalAssetsUsd!),
        ),
      if (data.topHoldingsWeightPct != null)
        QaStat(
          label: 'Peso del top ${holdings.length}',
          value: QaFormat.pct(data.topHoldingsWeightPct!),
        ),
    ];
    final subtitle = data.fundName ?? data.category;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QaTickerHeader(ticker: data.ticker, subtitle: subtitle),
        if (stats.isNotEmpty) ...[
          const SizedBox(height: QaSpace.sectionGap),
          QaStatGrid(stats: stats, columns: stats.length),
        ],
        if (holdings.isNotEmpty) ...[
          const SizedBox(height: QaSpace.sectionGap),
          const QaSectionLabel('Principales posiciones'),
          const SizedBox(height: 6),
          for (final h in holdings)
            _HoldingRow(holding: h, maxWeight: maxWeight),
        ],
        if (data.sectors.isNotEmpty) ...[
          const SizedBox(height: QaSpace.sectionGap),
          const QaSectionLabel('Sectores'),
          const SizedBox(height: 10),
          _SectorBlock(sectors: data.sectors),
        ],
        const SizedBox(height: QaSpace.gap),
        Text(
          holdings.isEmpty
              ? 'Según Yahoo Finance.'
              : 'Las ${holdings.length} posiciones más grandes del fondo, '
                  'no su cartera completa. Según Yahoo Finance.',
          style: QaText.caption,
        ),
        QaFollowUpBar(
          items: QaTickerFollowUps.of(
            data.ticker,
            // Un ETF no tiene earnings ni fundamentals de empresa.
            exclude: {
              QaTickerFollowUps.analysis,
              QaTickerFollowUps.earnings,
              QaTickerFollowUps.fundamentals,
            },
          ),
          limit: 3,
        ),
      ],
    );
  }
}

class _HoldingRow extends StatelessWidget {
  const _HoldingRow({required this.holding, required this.maxWeight});

  final EtfHolding holding;
  final double maxWeight;

  @override
  Widget build(BuildContext context) {
    final weight = holding.weightPct;
    return QaTappable(
      question: '¿Cómo viene ${holding.symbol}?',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              QaTickerAvatar(ticker: holding.symbol, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            holding.name ?? holding.symbol,
                            style: QaText.bodyStrong.copyWith(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (weight != null) ...[
                          const SizedBox(width: 8),
                          Text(QaFormat.pct(weight), style: QaText.valueSm),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        SizedBox(
                          width: 52,
                          child: Text(
                            holding.symbol,
                            style: QaText.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: QaProgressBar(
                            // Relativo a la más grande: con pesos de 2-10% la
                            // barra contra 100% casi no se vería.
                            value:
                                weight == null || maxWeight <= 0
                                    ? 0
                                    : weight / maxWeight,
                            height: 4,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectorBlock extends StatelessWidget {
  const _SectorBlock({required this.sectors});

  final List<EtfSectorWeight> sectors;

  @override
  Widget build(BuildContext context) {
    final shown = sectors.take(4).toList();
    final covered = shown.fold<double>(0, (a, s) => a + s.weightPct);
    final rest = 100 - covered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QaSegmentedBar(
          segments: [
            for (var i = 0; i < shown.length; i++)
              QaSegment(value: shown[i].weightPct, color: QaPalette.series(i)),
            if (rest > 0.5) QaSegment(value: rest, color: QaPalette.track),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (var i = 0; i < shown.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: QaPalette.series(i),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${shown[i].sector} ${QaFormat.pct(shown[i].weightPct)}',
                    style: QaText.label,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
