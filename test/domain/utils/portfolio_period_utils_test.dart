import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_period_utils.dart';

PortfolioHistoryPoint _p(int day, double value, double cost) =>
    PortfolioHistoryPoint(
      date: DateTime(2026, 9, day),
      totalValue: value,
      totalCostBasis: cost,
    );

void main() {
  test('a portfolio loaded at the end of the month: -7,94 \$ over 57 '
      'thousand is a tiny change, not -1,6%', () {
    final pnl = PortfolioPeriodUtils.periodPnlFromHistory([
      _p(12, 500, 500),
      _p(28, 500, 500),
      // Entraron 56.500 $ de posiciones nuevas.
      _p(30, 56992.06, 57000),
    ]);
    expect(pnl.absolute, closeTo(-7.94, 0.01));
    expect(pnl.percent.abs(), lessThan(0.1));
  });

  test('without new money it is the plain return on what was invested', () {
    final pnl = PortfolioPeriodUtils.periodPnlFromHistory([
      _p(1, 10000, 10000),
      _p(30, 10500, 10000),
    ]);
    expect(pnl.percent, closeTo(5, 1e-9));
  });
}
