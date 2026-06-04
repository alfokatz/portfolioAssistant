import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/features/analysis/catalog/analysis_colors.dart';
import 'package:portfolio_assistant/features/investment/utils/ticker_sector_map.dart';

class AssetDetailBottomSheet extends StatelessWidget {
  final String ticker;
  final double? currentPrice;
  final PortfolioSummary? summary;

  const AssetDetailBottomSheet({
    super.key,
    required this.ticker,
    this.currentPrice,
    this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final sector = TickerSectorMap.sectorFor(ticker);

    PositionInfo? position;
    if (summary != null) {
      for (final v in summary!.valuations) {
        if (v.position.ticker.toUpperCase() == ticker.toUpperCase()) {
          position = PositionInfo(
            shares: v.position.quantity,
            pnlAbsolute: v.pnlAbsolute,
            pnlPercent: v.pnlPercent,
            marketValue: v.marketValue,
          );
          break;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: const BoxDecoration(
        color: AnalysisColors.cardBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AnalysisColors.textSecondary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            ticker.toUpperCase(),
            style: const TextStyle(
              color: AnalysisColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            sector,
            style: const TextStyle(color: AnalysisColors.textSecondary),
          ),
          const SizedBox(height: 16),
          if (currentPrice != null)
            _row('Precio actual', currency.format(currentPrice)),
          if (position != null) ...[
            _row('En portfolio', '${position.shares} acciones'),
            _row('Valor', currency.format(position.marketValue)),
            _row(
              'P&L',
              '${position.pnlAbsolute >= 0 ? '+' : ''}'
              '${currency.format(position.pnlAbsolute)} '
              '(${position.pnlPercent.toStringAsFixed(1)}%)',
              valueColor: position.pnlAbsolute >= 0
                  ? AnalysisColors.profit
                  : AnalysisColors.loss,
            ),
          ] else
            const Text(
              'No tenés posición abierta en este activo.',
              style: TextStyle(color: AnalysisColors.textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AnalysisColors.textSecondary)),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AnalysisColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class PositionInfo {
  final double shares;
  final double pnlAbsolute;
  final double pnlPercent;
  final double marketValue;

  const PositionInfo({
    required this.shares,
    required this.pnlAbsolute,
    required this.pnlPercent,
    required this.marketValue,
  });
}
