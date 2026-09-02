import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/invest/budget_extractor.dart';

void main() {
  group('BudgetExtractor', () {
    test('extracts plain dollar amount', () {
      expect(BudgetExtractor.extractBudgetUsd('Quiero invertir \$500'), 500);
    });

    test('extracts amount with thousands separator comma', () {
      expect(BudgetExtractor.extractBudgetUsd('Tengo \$1,000 para invertir'), 1000);
    });

    test('extracts amount with thousands separator period', () {
      expect(BudgetExtractor.extractBudgetUsd('Presupuesto 1.000 USD'), 1000);
    });

    test('extracts a 4-digit amount with no thousands separator', () {
      // Regresión: la alternancia previa del regex matcheaba solo los
      // primeros 3 dígitos ("100") cuando no había separador de miles.
      expect(
        BudgetExtractor.extractBudgetUsd(
          'si tengo 1000 dólares para invertir y soy un inversor agresivo, '
          'que me recomendas?',
        ),
        1000,
      );
    });

    test('extracts a 5-digit amount with no thousands separator', () {
      expect(BudgetExtractor.extractBudgetUsd('Tengo 25000 para invertir'), 25000);
    });

    test('extracts \$-prefixed 4-digit amount with no separator', () {
      expect(BudgetExtractor.extractBudgetUsd('Quiero invertir \$1000'), 1000);
    });

    test('extracts decimal amount', () {
      expect(BudgetExtractor.extractBudgetUsd('Invertir 250.50'), 250.5);
    });

    test('returns null when no amount present', () {
      expect(BudgetExtractor.extractBudgetUsd('Quiero invertir en tech'), isNull);
    });

    test('returns null for zero amount', () {
      expect(BudgetExtractor.extractBudgetUsd('Invertir \$0'), isNull);
    });
  });
}
