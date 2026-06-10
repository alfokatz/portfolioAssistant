import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/ticker_sector_map.dart';

class SectorConcentration {
  const SectorConcentration({
    required this.sectorWeights,
    this.overweightSector,
    this.overweightPct,
  });

  final Map<String, double> sectorWeights;
  final String? overweightSector;
  final double? overweightPct;
}

abstract final class SectorConcentrationChecker {
  static const _overweightThresholdPct = 40.0;

  static SectorConcentration fromSummary(PortfolioSummary? summary) {
    if (summary == null || summary.valuations.isEmpty) {
      return const SectorConcentration(sectorWeights: {});
    }

    final sectorValues = <String, double>{};
    for (final valuation in summary.valuations) {
      final ticker = valuation.position.ticker.toUpperCase();
      final sector = sectorForTicker(ticker) ?? 'Other';
      sectorValues[sector] =
          (sectorValues[sector] ?? 0) + valuation.marketValue;
    }

    final total = summary.totalValue;
    final sectorWeights = <String, double>{};
    for (final entry in sectorValues.entries) {
      final weightPct = total > 0 ? (entry.value / total) * 100 : 0.0;
      sectorWeights[entry.key] = _round2(weightPct);
    }

    String? overweightSector;
    double? overweightPct;
    for (final entry in sectorWeights.entries) {
      if (entry.value > _overweightThresholdPct) {
        if (overweightPct == null || entry.value > overweightPct) {
          overweightSector = entry.key;
          overweightPct = entry.value;
        }
      }
    }

    return SectorConcentration(
      sectorWeights: sectorWeights,
      overweightSector: overweightSector,
      overweightPct: overweightPct,
    );
  }

  static double _round2(double value) =>
      double.parse(value.toStringAsFixed(2));
}
