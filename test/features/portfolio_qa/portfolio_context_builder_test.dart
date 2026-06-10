import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
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
      expect(json['has_closed_positions'], isFalse);
      expect(json['has_portfolio_data'], isFalse);
      expect(json['positions'], isEmpty);
      expect(json['closed_positions'], isEmpty);
    });

    test('closed-only portfolio includes realized pnl totals', () {
      final closed = [
        ClosedPosition(
          id: '1',
          ticker: 'AAPL',
          quantity: 2,
          avgPurchasePrice: 100,
          closePrice: 120,
          closeDate: DateTime(2026, 6, 1),
          closedAt: DateTime(2026, 6, 1),
        ),
        ClosedPosition(
          id: '2',
          ticker: 'TSLA',
          quantity: 1,
          avgPurchasePrice: 200,
          closePrice: 180,
          closeDate: DateTime(2026, 5, 15),
          closedAt: DateTime(2026, 5, 15),
        ),
      ];

      final json = jsonDecode(
        PortfolioContextBuilder.buildJson(null, closedPositions: closed),
      ) as Map;

      expect(json['has_positions'], isFalse);
      expect(json['has_closed_positions'], isTrue);
      expect(json['has_portfolio_data'], isTrue);
      expect(json['total_value'], 0);
      expect(json['closed_pnl_total_abs'], 20);
      expect((json['closed_positions'] as List).length, 2);
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

    test('includes period_returns distinct from all-time pnl', () {
      final summary = PortfolioSummary(
        totalValue: 1100,
        totalCostBasis: 900,
        totalPnlAbsolute: 200,
        totalPnlPercent: 22.22,
        valuations: [
          PositionValuation(
            position: Position(
              id: '1',
              ticker: 'AAPL',
              quantity: 1,
              purchasePrice: 900,
              purchaseDate: DateTime(2024, 1, 1),
            ),
            currentPrice: 1100,
            marketValue: 1100,
            pnlAbsolute: 200,
            pnlPercent: 22.22,
          ),
        ],
      );

      final history = [
        PortfolioHistoryPoint(
          date: DateTime(2026, 6, 2),
          totalValue: 1000,
          totalCostBasis: 900,
        ),
        PortfolioHistoryPoint(
          date: DateTime(2026, 6, 9),
          totalValue: 1100,
          totalCostBasis: 900,
        ),
      ];

      final json = jsonDecode(
        PortfolioContextBuilder.buildJson(summary, history: history),
      ) as Map;

      expect(json['total_pnl_abs'], 200);
      final week = json['period_returns']['week'] as Map;
      expect(week['pnl_abs'], 100);
      expect(week['has_sufficient_history'], isTrue);
      expect(week['label_es'], 'últimos 7 días');
    });

    test('includes position_periods when provided', () {
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
              purchasePrice: 900,
              purchaseDate: DateTime(2024, 1, 1),
            ),
            currentPrice: 1000,
            marketValue: 1000,
            pnlAbsolute: 100,
            pnlPercent: 11.11,
          ),
        ],
      );

      final positionPeriods = {
        'AAPL': {
          'week': {
            'label_es': 'últimos 7 días',
            'price_start': 198.5,
            'price_end': 190.16,
            'change_pct': -4.2,
            'has_sufficient_history': true,
          },
        },
      };

      final json = jsonDecode(
        PortfolioContextBuilder.buildJson(
          summary,
          positionPeriods: positionPeriods,
        ),
      ) as Map;

      final aaplWeek =
          (json['position_periods'] as Map)['AAPL']['week'] as Map;
      expect(aaplWeek['change_pct'], -4.2);
      expect(aaplWeek['has_sufficient_history'], isTrue);
    });
  });

  group('portfolioQaUserMessageBody', () {
    test('wraps snapshot, question and surface id', () {
      final body = portfolioQaUserMessageBody(
        portfolioSnapshotJson: '{"ticker":"AAPL"}',
        question: '¿Cómo voy?',
        surfaceId: 'portfolio_qa_0',
      );
      expect(body, contains('PORTFOLIO_SNAPSHOT'));
      expect(body, contains('¿Cómo voy?'));
      expect(body, contains('portfolio_qa_0'));
    });
  });
}
