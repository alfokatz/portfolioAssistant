import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_currency.dart';
import 'package:portfolio_assistant/features/display_currency/domain/fx_breakdown.dart';
import 'package:portfolio_assistant/features/display_currency/providers/display_currency_provider.dart';
import 'package:portfolio_assistant/features/display_currency/view/fx_breakdown_sheet.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required DisplayCurrency currency,
    double? rate = 40,
  }) async {
    SharedPreferences.setMockInitialValues({
      settingsDisplayCurrencyKey: currency.code,
    });
    final prefs = await SharedPreferences.getInstance();
    final theme = ProviderContainer().read(themeDataLightProvider);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          fxRateProvider.overrideWith((ref, c) async => rate),
          fxBreakdownProvider.overrideWith(
            (ref) async => FxBreakdown.compute(
              lots: [
                FxLot(
                  costUsd: 1000,
                  valueUsd: 1200,
                  purchaseDate: DateTime(2024),
                ),
              ],
              rateNow: 40,
              history: const [],
            ),
          ),
        ],
        child: MaterialApp(
          theme: theme,
          home: const Scaffold(body: DisplayCurrencyLine(totalUsd: 1000)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('con dólar no muestra nada', (tester) async {
    await pump(tester, currency: DisplayCurrency.usd);
    expect(find.textContaining('≈'), findsNothing);
  });

  testWidgets('sin tipo de cambio no muestra nada', (tester) async {
    await pump(tester, currency: DisplayCurrency.uyu, rate: null);
    expect(find.textContaining('≈'), findsNothing);
  });

  testWidgets('muestra el total convertido y abre el desglose', (tester) async {
    await pump(tester, currency: DisplayCurrency.uyu);
    expect(find.text('≈ \$U 40,000'), findsOneWidget);
    await tester.tap(find.byType(DisplayCurrencyLine));
    await tester.pumpAndSettle();
    expect(find.byType(FxBreakdownSheet), findsOneWidget);
    expect(find.text('fx_sheet_investments'), findsOneWidget);
    expect(find.text('+\$U 8,000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
