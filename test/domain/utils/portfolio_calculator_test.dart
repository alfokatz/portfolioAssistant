import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';

void main() {
  group('PortfolioCalculator.aggregateByTicker', () {
    test('combina varias compras del mismo ticker', () {
      final valuations = [
        PositionValuation(
          position: Position(
            id: '1',
            ticker: 'VOO',
            quantity: 1,
            purchasePrice: 500,
            purchaseDate: DateTime(2024, 1, 1),
          ),
          currentPrice: 700,
          marketValue: 700,
          pnlAbsolute: 200,
          pnlPercent: 40,
        ),
        PositionValuation(
          position: Position(
            id: '2',
            ticker: 'voo',
            quantity: 2,
            purchasePrice: 400,
            purchaseDate: DateTime(2024, 6, 1),
          ),
          currentPrice: 700,
          marketValue: 1400,
          pnlAbsolute: 600,
          pnlPercent: 75,
        ),
        PositionValuation(
          position: Position(
            id: '3',
            ticker: 'AAPL',
            quantity: 1,
            purchasePrice: 100,
            purchaseDate: DateTime(2024, 1, 1),
          ),
          currentPrice: 150,
          marketValue: 150,
          pnlAbsolute: 50,
          pnlPercent: 50,
        ),
      ];

      final summary = PortfolioCalculator.summarize(valuations);

      expect(summary.valuations.length, 2);

      final voo = summary.valuations.firstWhere(
        (v) => v.position.ticker == 'VOO',
      );
      expect(voo.position.quantity, 3);
      expect(voo.marketValue, 2100);
      expect(voo.position.costBasis, 1300);
      expect(voo.pnlAbsolute, 800);
      expect(voo.pnlPercent, closeTo(61.538, 0.01));
      expect(
        voo.position.purchasePrice,
        closeTo(1300 / 3, 0.0001),
      );

      expect(summary.totalValue, 2250);
      expect(summary.totalCostBasis, 1400);
      expect(summary.totalPnlAbsolute, 850);
    });
  });
}
