// Los montos de tu plata en la moneda elegida (DisplayMoneyScope): la fila
// de una posición y la card de ganancias. Sin scope, dólares.
// Correr: flutter test test/features/display_currency/display_money_scope_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_currency.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_money.dart';
import 'package:portfolio_assistant/features/display_currency/view/display_money_scope.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/pnl_distribution_card.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/position_row_widget.dart';

final _lot = PortfolioCalculator.valuate(
  position: Position(
    id: 'a',
    ticker: 'AAPL',
    quantity: 10,
    purchasePrice: 100,
    purchaseDate: DateTime(2026, 3, 1),
  ),
  currentPrice: 120,
);

Widget _app(Widget child, {DisplayMoney? money}) {
  final app = MaterialApp(
    theme: ProviderContainer().read(themeDataLightProvider),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
  return money == null ? app : DisplayMoneyScope(money: money, child: app);
}

void main() {
  const uyu = DisplayMoney(DisplayCurrency.uyu, 40);

  testWidgets('sin scope, la fila sigue en dólares', (tester) async {
    await tester.pumpWidget(_app(PositionRowWidget(valuation: _lot)));
    expect(find.text('\$1,200.00'), findsOneWidget);
  });

  testWidgets('en pesos: el valor de la posición en \$U, el % igual', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(PositionRowWidget(valuation: _lot), money: uyu),
    );
    expect(find.text('\$U 48,000'), findsOneWidget);
    expect(find.text('+20.0%'), findsOneWidget);
    expect(find.textContaining('\$1,200'), findsNothing);
  });

  testWidgets('la card de ganancias por posición, en pesos', (tester) async {
    await tester.pumpWidget(
      _app(PnlDistributionCard(valuations: [_lot]), money: uyu),
    );
    // Ganancia 10 × 20 = 200 dólares → $U 8.000.
    expect(find.textContaining('+\$U 8,000'), findsWidgets);
  });

  test('DisplayMoney: misma moneda y tipo de cambio son iguales', () {
    expect(uyu, const DisplayMoney(DisplayCurrency.uyu, 40));
    expect(uyu == const DisplayMoney(DisplayCurrency.uyu, 41), isFalse);
  });
}
