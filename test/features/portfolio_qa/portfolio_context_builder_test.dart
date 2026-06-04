import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/features/portfolio_qa/prompts/portfolio_qa_system_prompt.dart';
import 'package:portfolio_assistant/features/portfolio_qa/utils/portfolio_context_builder.dart';

void main() {
  group('PortfolioContextBuilder', () {
    test('empty summary marks has_positions false', () {
      final json = jsonDecode(PortfolioContextBuilder.buildJson(null)) as Map;
      expect(json['has_positions'], isFalse);
      expect(json['positions'], isEmpty);
    });

    test('includes weighted positions', () {
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
              ticker: 'MSFT',
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

      final json = jsonDecode(PortfolioContextBuilder.buildJson(summary)) as Map;
      expect(json['has_positions'], isTrue);
      expect(json['total_value'], 1000);

      final positions = json['positions'] as List;
      expect(positions.length, 2);
      expect(positions.first['ticker'], 'AAPL');
      expect(positions.first['weight_pct'], 30.0);
    });
  });

  group('portfolioQaSystemPrompt', () {
    test('includes disclaimer and no trade orders rule', () {
      expect(portfolioQaSystemPrompt, contains('educativa'));
      expect(portfolioQaSystemPrompt, contains('NO des órdenes'));
    });

    test('user message wraps snapshot and question', () {
      final body = portfolioQaUserMessageBody(
        portfolioSnapshotJson: '{"ticker":"AAPL"}',
        question: '¿Cómo voy?',
      );
      expect(body, contains('PORTFOLIO_SNAPSHOT'));
      expect(body, contains('¿Cómo voy?'));
    });
  });
}
