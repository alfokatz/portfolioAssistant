import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/allocation/domain/allocation_plan.dart';

import '../../helpers/property.dart';

int _sum(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

/// Reglas del plan de cartera que valen para cualquier cartera: los repartos
/// en porcentaje suman 100, nada queda negativo ni NaN, y un aporte nunca se
/// reparte de más.
void main() {
  group('AllocationMath', () {
    property<List<String>>(
      'equalSplit suma 100 y nadie queda negativo',
      generate: (r) => Gen.tickers(r, min: 1),
      check: (tickers) {
        final split = AllocationMath.equalSplit(tickers);
        expect(_sum(split), 100);
        expect(split.values.every((v) => v >= 0), isTrue);
        // Partes iguales: la diferencia entre el mayor y el menor es ≤ 1.
        final vs = split.values.toList()..sort();
        expect(vs.last - vs.first, lessThanOrEqualTo(1));
      },
    );

    property<(List<String>, Map<String, double>)>(
      'initialSplit suma 100 con lo elegido, tenga o no algo de eso',
      generate: (r) {
        final tickers = Gen.tickers(r, min: 1);
        final values = {for (final t in Gen.tickers(r)) t: Gen.amount(r)};
        return (tickers, values);
      },
      check: (input) {
        final (tickers, values) = input;
        final split = AllocationMath.initialSplit(
          tickers: tickers,
          values: values,
        );
        expect(split.keys.toSet(), tickers.toSet());
        expect(_sum(split), 100);
        expect(split.values.every((v) => v >= 0), isTrue);
      },
    );

    property<(Map<String, int>, String, int, Set<String>)>(
      'rebalance mantiene la suma, respeta los fijos y es idempotente',
      generate: (r) {
        final tickers = Gen.tickers(r, min: 2);
        final targets = AllocationMath.equalSplit(tickers);
        final ticker = tickers[r.nextInt(tickers.length)];
        final locked = {
          for (final t in tickers)
            if (t != ticker && r.nextInt(4) == 0) t,
        };
        return (targets, ticker, r.nextInt(130) - 15, locked);
      },
      check: (input) {
        final (targets, ticker, value, locked) = input;
        final out = AllocationMath.rebalance(
          targets: targets,
          ticker: ticker,
          value: value,
          locked: locked,
        );
        expect(_sum(out), 100);
        expect(out.values.every((v) => v >= 0), isTrue);
        for (final t in locked) {
          expect(out[t], targets[t], reason: 'un fijo no se mueve ($t)');
        }
        // Mover al mismo valor otra vez no cambia nada.
        final again = AllocationMath.rebalance(
          targets: out,
          ticker: ticker,
          value: out[ticker]!,
          locked: locked,
        );
        expect(again, out);
      },
    );

    property<(Map<String, int>, String)>(
      'remove le pasa lo suyo a los demás y la suma sigue en 100',
      generate: (r) {
        final tickers = Gen.tickers(r, min: 2);
        return (
          AllocationMath.equalSplit(tickers),
          tickers[r.nextInt(tickers.length)],
        );
      },
      check: (input) {
        final (targets, ticker) = input;
        final out = AllocationMath.remove(targets, ticker);
        expect(out.containsKey(ticker), isFalse);
        expect(_sum(out), 100);
      },
    );

    property<Map<String, double>>(
      'roundTo100 y fromCurrentWeights suman exactamente 100 si hay algo',
      generate:
          (r) => {for (final t in Gen.tickers(r, min: 1)) t: Gen.amount(r)},
      check: (values) {
        final hasPositive = values.values.any((v) => v > 0);
        for (final out in [
          AllocationMath.roundTo100(values),
          AllocationMath.fromCurrentWeights(values),
        ]) {
          if (!hasPositive) {
            expect(out, isEmpty);
            continue;
          }
          expect(out.values.fold(0.0, (a, b) => a + b), 100);
          expect(
            out.values.every((v) => v > 0 && v == v.roundToDouble()),
            isTrue,
          );
        }
      },
    );

    property<(Map<String, double>, Map<String, double>)>(
      'rows: los pesos actuales suman 100 (o 0 sin valor) y nunca son NaN',
      generate:
          (r) => (
            {for (final t in Gen.tickers(r)) t: Gen.amount(r)},
            {for (final t in Gen.tickers(r)) t: r.nextInt(101).toDouble()},
          ),
      check: (input) {
        final (values, targets) = input;
        final rows = AllocationMath.rows(values: values, targets: targets);
        final total = values.values
            .where((v) => v > 0)
            .fold(0.0, (a, b) => a + b);
        final pctSum = rows.fold(0.0, (a, r) => a + r.currentPct);
        expect(
          rows.every((r) => r.currentPct.isFinite && r.drift.isFinite),
          isTrue,
        );
        expect(pctSum, total > 0 ? closeTo(100, 1e-6) : 0);
        expect(AllocationMath.maxDrift(rows), greaterThanOrEqualTo(0));
      },
    );

    property<(Map<String, double>, Map<String, double>, double)>(
      'contribution reparte el aporte (±1 centavo por ticker) y solo compra',
      generate: (r) {
        final plan = AllocationMath.equalSplit(Gen.tickers(r, min: 1));
        return (
          {for (final t in Gen.tickers(r)) t: Gen.amount(r)},
          {for (final e in plan.entries) e.key: e.value.toDouble()},
          Gen.amount(r),
        );
      },
      check: (input) {
        final (values, targets, amount) = input;
        final split = AllocationMath.contribution(
          values: values,
          targets: targets,
          amount: amount,
        );
        expect(split.values.every((v) => v.isFinite && v >= 0), isTrue);
        expect(split.keys.every(targets.containsKey), isTrue);
        if (split.isNotEmpty) {
          final total = split.values.fold(0.0, (a, b) => a + b);
          expect(total, closeTo(amount, 0.01 * split.length + 1e-9));
        }
      },
    );
  });

  group('AllocationPlan', () {
    property<AllocationPlan>(
      'ida y vuelta: fromRow(toRow(plan)) devuelve el mismo plan',
      generate: (r) {
        final day = r.nextBool() ? 1 + r.nextInt(28) : null;
        return AllocationPlan(
          targets: AllocationMath.fromCurrentWeights({
            for (final t in Gen.tickers(r)) t: Gen.amount(r) + 1,
          }),
          driftThreshold: (1 + r.nextInt(20)).toDouble(),
          notify: r.nextBool(),
          frequency:
              AllocationAlertFrequency.values[r.nextInt(
                AllocationAlertFrequency.values.length,
              )],
          contributionDay: day,
          contributionAmount:
              day != null && r.nextBool()
                  ? (r.nextInt(100000) + 1) / 100
                  : null,
        );
      },
      check: (plan) {
        expect(AllocationPlan.fromRow(plan.toRow()), plan);
      },
    );
  });
}
