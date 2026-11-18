// Montos de una meta en su moneda (ver goal_money.dart).
// Correr: flutter test test/features/goals/goal_money_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_currency.dart';
import 'package:portfolio_assistant/features/goals/view/goal_money.dart';

void main() {
  test('en dólares, como siempre; en pesos, con su símbolo y sin centavos', () {
    expect(goalMoney(DisplayCurrency.usd, 1500), '\$1,500');
    expect(goalMoney(DisplayCurrency.uyu, 1000000), '\$U 1,000,000');
    expect(goalMoney(DisplayCurrency.brl, 2500.4), 'R\$ 2,500');
  });
}
