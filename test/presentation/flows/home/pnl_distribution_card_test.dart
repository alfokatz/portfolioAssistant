// P&L por activo: con datos raros (precio NaN o infinito) no puede quedar en
// blanco. Correr: flutter test test/presentation/flows/home/pnl_distribution_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/ui/widgets/pnl_distribution_card.dart';

void main() {
  Future<void> pump(WidgetTester tester, List<double> prices) async {
    final probe = ProviderContainer();
    await tester.pumpWidget(
      MaterialApp(
        theme: probe.read(themeDataDarkProvider),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PnlDistributionCard(
              valuations: [
                for (var i = 0; i < prices.length; i++)
                  PortfolioCalculator.valuate(
                    position: Position(
                      id: '$i',
                      ticker: 'T$i',
                      quantity: 1,
                      purchasePrice: 100,
                      purchaseDate: DateTime(2025),
                    ),
                    currentPrice: prices[i],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('una cotización NaN no rompe la tarjeta', (tester) async {
    await pump(tester, [120, double.nan, 80]);
    expect(tester.takeException(), isNull);
    expect(find.text('T0'), findsWidgets);
    expect(find.text('T2'), findsWidgets);
  });

  testWidgets('precio infinito o cero tampoco', (tester) async {
    await pump(tester, [double.infinity, 0, 90]);
    expect(tester.takeException(), isNull);
    expect(find.text('T2'), findsWidgets);
  });

  testWidgets('con datos normales dibuja las filas', (tester) async {
    await pump(tester, [120, 95, 80, 130, 101, 99, 70]);
    expect(tester.takeException(), isNull);
    expect(find.text('T3'), findsWidgets);
  });
}
