import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';

void main() {
  test('calcula rentabilidad final al cerrar', () {
    final position = ClosedPosition(
      id: '1',
      ticker: 'VOO',
      quantity: 2,
      avgPurchasePrice: 500,
      closePrice: 700,
      closeDate: DateTime(2025, 1, 15),
      closedAt: DateTime(2025, 1, 16),
    );

    expect(position.costBasis, 1000);
    expect(position.proceeds, 1400);
    expect(position.pnlAbsolute, 400);
    expect(position.pnlPercent, 40);
  });

  test('calcula rentabilidad de venta parcial', () {
    final partial = ClosedPosition(
      id: '2',
      ticker: 'AAPL',
      quantity: 0.5,
      avgPurchasePrice: 100,
      closePrice: 150,
      closeDate: DateTime(2025, 6, 1),
      closedAt: DateTime(2025, 6, 2),
    );

    expect(partial.costBasis, 50);
    expect(partial.proceeds, 75);
    expect(partial.pnlAbsolute, 25);
    expect(partial.pnlPercent, 50);
  });
}
