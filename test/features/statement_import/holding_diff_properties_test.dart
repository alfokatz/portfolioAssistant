import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/statement_import/domain/holding_change.dart';
import 'package:portfolio_assistant/features/statement_import/domain/import_row.dart';

import '../../helpers/property.dart';

/// Lo que queda en manuales después de aplicar el plan de una fila.
double _apply(ImportPlan p, double have) => switch (p.action) {
  ImportAction.add => have + p.quantity,
  ImportAction.buyMore => have + p.quantity,
  ImportAction.sell => have - p.quantity,
  ImportAction.unchanged => have,
};

typedef _Case = (ImportRow row, HeldHolding? held, double? price);

/// Importar un estado de cuenta es idempotente: importar el mismo archivo dos
/// veces no compra ni vende nada la segunda vez (el equivalente a "reintentar
/// un pago nunca cobra dos veces"). Ver b6d69e6 (doble toque importaba dos veces).
void main() {
  _Case generate(r) {
    final fromAmount = r.nextInt(4) == 0;
    final row = ImportRow(
      id: 0,
      ticker: Gen.ticker(r),
      quantity: Gen.quantity(r),
      purchasePrice: r.nextBool() ? Gen.amount(r) + 0.01 : null,
      quantityFromAmount: fromAmount,
    );
    final held = switch (r.nextInt(4)) {
      0 => null,
      1 => HeldHolding(quantity: 0, costBasis: 0),
      // Casi lo mismo que el archivo (redondeos del bróker).
      2 => HeldHolding(
        quantity: row.quantity * (1 + (r.nextDouble() - 0.5) * 1e-5),
        costBasis: Gen.amount(r),
      ),
      _ => HeldHolding(quantity: Gen.quantity(r), costBasis: Gen.amount(r)),
    };
    return (row, held, r.nextBool() ? Gen.amount(r) + 0.01 : null);
  }

  group('HoldingDiff.plan', () {
    property<_Case>(
      'después de aplicar el plan, la misma fila no cambia nada',
      runs: 2000,
      generate: generate,
      check: (c) {
        final (row, held, price) = c;
        final first = HoldingDiff.plan(row, held, price);
        final after = _apply(first, held?.quantity ?? 0);
        final second = HoldingDiff.plan(
          row,
          HeldHolding(quantity: after, costBasis: held?.costBasis ?? 0),
          price,
        );
        expect(
          second.action,
          ImportAction.unchanged,
          reason:
              'primera: ${first.action} ${first.quantity}, '
              'quedó en $after, segunda: ${second.action} ${second.quantity}',
        );
      },
    );

    property<_Case>(
      'nunca vende más de lo que hay ni mueve cantidades negativas o NaN',
      runs: 2000,
      generate: generate,
      check: (c) {
        final (row, held, price) = c;
        final p = HoldingDiff.plan(row, held, price);
        expect(p.quantity.isFinite && p.quantity >= 0, isTrue);
        if (p.action == ImportAction.sell) {
          expect(p.quantity, lessThanOrEqualTo(held!.quantity + 1e-8));
        }
        if (p.price != null) expect(p.price!.isFinite && p.price! > 0, isTrue);
      },
    );
  });
}
