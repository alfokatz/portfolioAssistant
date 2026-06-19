import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/sector_display_name.dart';
import 'package:portfolio_assistant/features/assistant/utils/portfolio_context_builder.dart';

void main() {
  group('PortfolioContextBuilder sectors', () {
    test('includes sector per position and sector_concentration', () {
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
            marketValue: 300,
            pnlAbsolute: 100,
            pnlPercent: 50,
          ),
          PositionValuation(
            position: Position(
              id: '2',
              ticker: 'GGAL',
              quantity: 1,
              purchasePrice: 200,
              purchaseDate: DateTime(2024, 1, 1),
            ),
            currentPrice: 700,
            marketValue: 700,
            pnlAbsolute: 500,
            pnlPercent: 250,
          ),
        ],
      );

      const sectorByTicker = {
        'AAPL': 'Tecnología',
        'GGAL': 'Finanzas',
      };

      final json = jsonDecode(
        PortfolioContextBuilder.buildJson(
          summary,
          sectorByTicker: sectorByTicker,
        ),
      ) as Map<String, dynamic>;

      final positions = json['positions'] as List;
      expect(positions.first['sector'], 'Tecnología');
      expect(positions.last['sector'], 'Finanzas');

      final concentration = json['sector_concentration'] as Map;
      expect(concentration['Tecnología'], 30.0);
      expect(concentration['Finanzas'], 70.0);
      expect(json['concentration_warning'], isTrue);
      expect(json['overweight_sector'], 'Finanzas');
    });

    test('defaults missing sectors to Sin clasificar', () {
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
              purchasePrice: 400,
              purchaseDate: DateTime(2024, 1, 1),
            ),
            currentPrice: 500,
            marketValue: 500,
            pnlAbsolute: 100,
            pnlPercent: 25,
          ),
        ],
      );

      final json = jsonDecode(PortfolioContextBuilder.buildJson(summary))
          as Map<String, dynamic>;

      final positions = json['positions'] as List;
      expect(positions.first['sector'], SectorDisplayName.unclassified);
      expect(
        (json['sector_concentration'] as Map)[SectorDisplayName.unclassified],
        100.0,
      );
    });
  });
}
