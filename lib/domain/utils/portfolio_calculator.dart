import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';

class PortfolioCalculator {
  static String normalizeTicker(String ticker) {
    return ticker.trim().toUpperCase();
  }

  /// Yahoo Finance uses dashes for share classes (e.g. BRK.B → BRK-B).
  static String toYahooFinanceSymbol(String ticker) {
    return normalizeTicker(ticker).replaceAll('.', '-');
  }

  static PositionValuation valuate({
    required Position position,
    required double currentPrice,
  }) {
    final marketValue = position.quantity * currentPrice;
    final costBasis = position.costBasis;
    final pnlAbsolute = marketValue - costBasis;
    final pnlPercent = costBasis > 0 ? (pnlAbsolute / costBasis) * 100 : 0.0;

    return PositionValuation(
      position: position,
      currentPrice: currentPrice,
      marketValue: marketValue,
      pnlAbsolute: pnlAbsolute,
      pnlPercent: pnlPercent,
    );
  }

  /// Combina varias compras del mismo ticker en una sola valoración.
  static List<PositionValuation> aggregateByTicker(
    List<PositionValuation> valuations,
  ) {
    if (valuations.isEmpty) return [];

    final byTicker = <String, List<PositionValuation>>{};
    for (final valuation in valuations) {
      final key = normalizeTicker(valuation.position.ticker);
      byTicker.putIfAbsent(key, () => []).add(valuation);
    }

    final aggregated = byTicker.entries.map((entry) {
      final group = entry.value;
      if (group.length == 1) return group.first;

      final totalQuantity = group.fold<double>(
        0,
        (sum, v) => sum + v.position.quantity,
      );
      final totalCostBasis = group.fold<double>(
        0,
        (sum, v) => sum + v.position.costBasis,
      );
      final totalMarketValue = group.fold<double>(
        0,
        (sum, v) => sum + v.marketValue,
      );
      final totalPnlAbsolute = totalMarketValue - totalCostBasis;
      final totalPnlPercent = totalCostBasis > 0
          ? (totalPnlAbsolute / totalCostBasis) * 100
          : 0.0;
      final avgPurchasePrice =
          totalQuantity > 0 ? totalCostBasis / totalQuantity : 0.0;
      final earliestPurchase = group
          .map((v) => v.position.purchaseDate)
          .reduce((a, b) => a.isBefore(b) ? a : b);

      return PositionValuation(
        position: Position(
          id: entry.key,
          ticker: entry.key,
          quantity: totalQuantity,
          purchasePrice: avgPurchasePrice,
          purchaseDate: earliestPurchase,
        ),
        currentPrice: group.first.currentPrice,
        marketValue: totalMarketValue,
        pnlAbsolute: totalPnlAbsolute,
        pnlPercent: totalPnlPercent,
      );
    }).toList();

    aggregated.sort((a, b) => b.marketValue.compareTo(a.marketValue));
    return aggregated;
  }

  static PortfolioSummary summarize(List<PositionValuation> valuations) {
    if (valuations.isEmpty) {
      return const PortfolioSummary(
        totalValue: 0,
        totalCostBasis: 0,
        totalPnlAbsolute: 0,
        totalPnlPercent: 0,
        valuations: [],
      );
    }

    final totalValue =
        valuations.fold<double>(0, (sum, v) => sum + v.marketValue);
    final totalCostBasis =
        valuations.fold<double>(0, (sum, v) => sum + v.position.costBasis);
    final totalPnlAbsolute = totalValue - totalCostBasis;
    final totalPnlPercent =
        totalCostBasis > 0 ? (totalPnlAbsolute / totalCostBasis) * 100 : 0.0;

    return PortfolioSummary(
      totalValue: totalValue,
      totalCostBasis: totalCostBasis,
      totalPnlAbsolute: totalPnlAbsolute,
      totalPnlPercent: totalPnlPercent,
      valuations: aggregateByTicker(valuations),
    );
  }
}
