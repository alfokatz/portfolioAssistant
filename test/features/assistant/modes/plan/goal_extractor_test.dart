import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/modes/plan/goal_extractor.dart';

void main() {
  group('GoalExtractor', () {
    final asOf = DateTime(2026, 6, 10);

    test('extractTargetAmount parses dollar amounts', () {
      expect(GoalExtractor.extractTargetAmount('Quiero ahorrar \$50.000'), 50000);
      expect(GoalExtractor.extractTargetAmount('Meta de 1,000 USD'), 1000);
    });

    test('extractTargetDate parses years from now', () {
      final date = GoalExtractor.extractTargetDate(
        'Quiero jubilarme en 5 años',
        asOf: asOf,
      );

      expect(date, DateTime(2031, 6, 10));
    });

    test('extractTargetDate parses explicit year', () {
      final date = GoalExtractor.extractTargetDate(
        'Necesito \$20k para 2030',
        asOf: asOf,
      );

      expect(date, DateTime(2030));
    });

    test('extractTargetDate parses month and year in Spanish', () {
      final date = GoalExtractor.extractTargetDate(
        'Meta en diciembre 2028',
        asOf: asOf,
      );

      expect(date, DateTime(2028, 12));
    });

    test('extractTargetDate returns null when no date present', () {
      expect(
        GoalExtractor.extractTargetDate('Quiero ahorrar más', asOf: asOf),
        isNull,
      );
    });

    test('extractGoalLabel returns parsed label or default', () {
      expect(
        GoalExtractor.extractGoalLabel('Meta de jubilación con \$50k'),
        'Jubilación Con',
      );
      expect(
        GoalExtractor.extractGoalLabel('Quiero ahorrar para un auto'),
        'Auto',
      );
      expect(GoalExtractor.extractGoalLabel('Cuánto me falta'), 'Mi meta');
    });
  });
}
