import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_currency.dart';
import 'package:portfolio_assistant/features/display_currency/domain/fx_breakdown.dart';
import 'package:portfolio_assistant/features/display_currency/providers/display_currency_provider.dart';
import 'package:portfolio_assistant/features/display_currency/view/fx_breakdown_sheet.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // La cara de Porty (PortySays) no se anima sola: pumpAndSettle termina.
  setUpAll(() => PortyAvatar.ambientMotion = false);
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
          home: const Scaffold(body: DisplayTotalLabel()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('con dólar dice "Total" y no abre nada', (tester) async {
    await pump(tester, currency: DisplayCurrency.usd);
    expect(find.text('portfolio_total_label'), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('sin tipo de cambio sigue en dólares: "Total"', (tester) async {
    await pump(tester, currency: DisplayCurrency.uyu, rate: null);
    expect(find.text('portfolio_total_label'), findsOneWidget);
    expect(find.text('fx_total_label'), findsNothing);
  });

  testWidgets('con otra moneda dice en cuál y abre el desglose', (
    tester,
  ) async {
    await pump(tester, currency: DisplayCurrency.uyu);
    expect(find.text('fx_total_label'), findsOneWidget);
    await tester.tap(find.byType(DisplayTotalLabel));
    await tester.pumpAndSettle();
    expect(find.byType(FxBreakdownSheet), findsOneWidget);
    expect(find.text('fx_sheet_investments'), findsOneWidget);
    // Porty encabeza con cuánto movió el tipo de cambio.
    expect(
      find.textContaining(RegExp('fx_porty_(up|down|flat)')),
      findsOneWidget,
    );
    expect(find.text('+\$U 8,000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
