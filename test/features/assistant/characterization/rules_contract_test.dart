import 'package:flutter_test/flutter_test.dart';

import 'rules_contract.dart';

/// El helper tiene que acotar cada sección a su propio bloque: si
/// devolviera "todo lo que sigue", los casos contrato pasarían
/// trivialmente con cualquier widget de cualquier sección.
void main() {
  const rules = '''
RULES:

TEMPORAL QUESTIONS (CRITICAL)
- "hoy" → period_returns.day
Use QaPeriodChange.

NEVER use QaPnLBreakdown here.

LAYOUT (mandatory structure)
1. QaAnswerText

WIDGET SELECTION GUIDE
- Compare two tickers: QaComparisonRow
''';

  test('a section stops at the next header, not at inner ALL-CAPS words', () {
    final temporal = ruleSection(rules, 'TEMPORAL QUESTIONS');
    expect(temporal, contains('Use QaPeriodChange.'));
    expect(temporal, contains('NEVER use QaPnLBreakdown here.'));
    expect(temporal, isNot(contains('QaAnswerText')));
    expect(temporal, isNot(contains('QaComparisonRow')));
  });

  test('headers with a lowercase parenthetical are recognized', () {
    final layout = ruleSection(rules, 'LAYOUT');
    expect(layout, contains('1. QaAnswerText'));
    expect(layout, isNot(contains('QaComparisonRow')));
  });

  test('the last section runs to the end', () {
    expect(
      ruleSection(rules, 'WIDGET SELECTION GUIDE'),
      contains('QaComparisonRow'),
    );
  });
}
