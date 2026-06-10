import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/sector_concentration_checker.dart';

void main() {
  group('SectorConcentrationChecker', () {
    test('returns empty weights when summary is null', () {
      final result = SectorConcentrationChecker.fromSummary(null);

      expect(result.sectorWeights, isEmpty);
      expect(result.overweightSector, isNull);
      expect(result.overweightPct, isNull);
    });

    test('returns empty weights when no open positions', () {
      final summary = PortfolioSummary(
        totalValue: 0,
        totalCostBasis: 0,
        totalPnlAbsolute: 0,
        totalPnlPercent: 0,
        valuations: const [],
      );

      final result = SectorConcentrationChecker.fromSummary(summary);
      expect(result.sectorWeights, isEmpty);
    });

    test('computes sector weights and flags overweight sector', () {
      final summary = PortfolioSummary(
        totalValue: 1000,
        totalCostBasis: 900,
        totalPnlAbsolute: 100,
        totalPnlPercent: 11.11,
        valuations: [
          PositionValuation(
            position: Position(
              id: '1',
              ticker: 'AAPL',
              quantity: 2,
              purchasePrice: 100,
              purchaseDate: DateTime(2024, 1, 1),
            ),
            currentPrice: 150,
            marketValue: 450,
            pnlAbsolute: 100,
            pnlPercent: 50,
          ),
          PositionValuation(
            position: Position(
              id: '2',
              ticker: 'MSFT',
              quantity: 1,
              purchasePrice: 200,
              purchaseDate: DateTime(2024, 1, 1),
            ),
            currentPrice: 550,
            marketValue: 550,
            pnlAbsolute: 100,
            pnlPercent: 14.29,
          ),
        ],
      );

      final result = SectorConcentrationChecker.fromSummary(summary);

      expect(result.sectorWeights['Technology'], 100.0);
      expect(result.overweightSector, 'Technology');
      expect(result.overweightPct, 100.0);
    });

    test('buckets unknown tickers as Other', () {
      final summary = PortfolioSummary(
        totalValue: 500,
        totalCostBasis: 400,
        totalPnlAbsolute: 100,
        totalPnlPercent: 25,
        valuations: [
          PositionValuation(
            position: Position(
              id: '1',
              ticker: 'UNKNOWN',
              quantity: 1,
              purchasePrice: 100,
              purchaseDate: DateTime(2024, 1, 1),
            ),
            currentPrice: 500,
            marketValue: 500,
            pnlAbsolute: 100,
            pnlPercent: 25,
          ),
        ],
      );

      final result = SectorConcentrationChecker.fromSummary(summary);

      expect(result.sectorWeights['Other'], 100.0);
      expect(result.overweightSector, 'Other');
    });

    test('does not flag overweight when all sectors below 40%', () {
      final summary = PortfolioSummary(
        totalValue: 1000,
        totalCostBasis: 900,
        totalPnlAbsolute: 100,
        totalPnlPercent: 11.11,
        valuations: [
          PositionValuation(
            position: Position(
              id: '1',
              ticker: 'AAPL',
              quantity: 1,
              purchasePrice: 100,
              purchaseDate: DateTime(2024, 1, 1),
            ),
            currentPrice: 300,
            marketValue: 300,
            pnlAbsolute: 100,
            pnlPercent: 50,
          ),
          PositionValuation(
            position: Position(
              id: '2',
              ticker: 'JPM',
              quantity: 1,
              purchasePrice: 200,
              purchaseDate: DateTime(2024, 1, 1),
            ),
            currentPrice: 350,
            marketValue: 350,
            pnlAbsolute: 100,
            pnlPercent: 14.29,
          ),
          PositionValuation(
            position: Position(
              id: '3',
              ticker: 'XOM',
              quantity: 1,
              purchasePrice: 200,
              purchaseDate: DateTime(2024, 1, 1),
            ),
            currentPrice: 350,
            marketValue: 350,
            pnlAbsolute: 100,
            pnlPercent: 14.29,
          ),
        ],
      );

      final result = SectorConcentrationChecker.fromSummary(summary);

      expect(result.sectorWeights['Technology'], 30.0);
      expect(result.sectorWeights['Financials'], 35.0);
      expect(result.sectorWeights['Energy'], 35.0);
      expect(result.overweightSector, isNull);
      expect(result.overweightPct, isNull);
    });
  });
}
