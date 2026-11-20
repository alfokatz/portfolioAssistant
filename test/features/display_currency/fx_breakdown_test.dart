import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_currency.dart';
import 'package:portfolio_assistant/features/display_currency/domain/fx_breakdown.dart';
import 'package:portfolio_assistant/features/display_currency/providers/display_currency_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

PriceCandle _c(int y, int m, int d, double close) =>
    PriceCandle(date: DateTime(y, m, d), close: close);

void main() {
  group('FxBreakdown.compute', () {
    test('separa la ganancia en inversiones y tipo de cambio, y suman', () {
      // Compró USD 1000 cuando el dólar valía 38; hoy vale 1200 y el dólar 42.
      final b = FxBreakdown.compute(
        lots: [
          FxLot(
            costUsd: 1000,
            valueUsd: 1200,
            purchaseDate: DateTime(2024, 3, 15),
          ),
        ],
        rateNow: 42,
        history: [
          _c(2024, 3, 14, 37.5),
          _c(2024, 3, 15, 38),
          _c(2024, 3, 18, 39),
        ],
      );
      expect(b.cost, 38000);
      expect(b.value, 50400);
      expect(b.gain, 12400);
      expect(b.investmentEffect, 8400); // 200 USD × 42
      expect(b.currencyEffect, 4000); // 1000 USD × (42 − 38)
      expect(b.investmentEffect + b.currencyEffect, closeTo(b.gain, 1e-9));
      expect(b.lotsWithoutHistory, 0);
    });

    test('fin de semana: usa el último cierre anterior', () {
      final history = [_c(2024, 3, 15, 38), _c(2024, 3, 18, 39)];
      // Sábado 16 → viernes 15.
      expect(FxBreakdown.rateOn(history, DateTime(2024, 3, 16), 1), (
        38.0,
        true,
      ));
    });

    test('compra anterior al histórico: primer valor y se cuenta', () {
      final b = FxBreakdown.compute(
        lots: [
          FxLot(costUsd: 100, valueUsd: 100, purchaseDate: DateTime(2000)),
          FxLot(
            costUsd: 100,
            valueUsd: 100,
            purchaseDate: DateTime(2024, 5, 1),
          ),
        ],
        rateNow: 40,
        history: [_c(2024, 4, 1, 35), _c(2010, 1, 4, 20)],
      );
      expect(b.lotsWithoutHistory, 1);
      // Primera compra con 20 (lo más viejo), segunda con 35.
      expect(b.cost, 100 * 20 + 100 * 35);
      expect(b.currencyEffect, 100 * (40 - 20) + 100 * (40 - 35));
    });

    test(
      'sin histórico: todo al tipo de cambio de hoy (sin efecto cambiario)',
      () {
        final b = FxBreakdown.compute(
          lots: [
            FxLot(costUsd: 100, valueUsd: 90, purchaseDate: DateTime(2024)),
          ],
          rateNow: 10,
          history: const [],
        );
        expect(b.currencyEffect, 0);
        expect(b.gain, -100);
        expect(b.gainPercent, -10);
        expect(b.lotsWithoutHistory, 1);
      },
    );
  });

  group('DisplayCurrency', () {
    test('símbolo de Yahoo y formato sin centavos para pesos', () {
      expect(DisplayCurrency.uyu.yahooSymbol, 'UYU=X');
      expect(DisplayCurrency.uyu.money(1234567.4), '\$U 1,234,567');
      expect(DisplayCurrency.eur.signedMoney(-12.5), '-€12.50');
      expect(DisplayCurrency.fromCode('BRL'), DisplayCurrency.brl);
      expect(DisplayCurrency.fromCode('XXX'), DisplayCurrency.usd);
      expect(DisplayCurrency.fromCode(null), DisplayCurrency.usd);
    });

    test('la preferencia se guarda en el teléfono', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final n = DisplayCurrencyNotifier(prefs);
      expect(n.state, DisplayCurrency.usd);
      await n.set(DisplayCurrency.ars);
      expect(DisplayCurrencyNotifier(prefs).state, DisplayCurrency.ars);
    });
  });
}
