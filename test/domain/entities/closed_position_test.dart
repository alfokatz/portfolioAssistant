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
}
