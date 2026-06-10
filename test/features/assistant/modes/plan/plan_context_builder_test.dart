import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/features/assistant/modes/plan/plan_context_builder.dart';

void main() {
  group('PlanContextBuilder', () {
    final asOf = DateTime.utc(2026, 6, 10, 12, 0);
    final summary = PortfolioSummary(
      totalValue: 12000,
      totalCostBasis: 10000,
      totalPnlAbsolute: 2000,
      totalPnlPercent: 20,
      valuations: const [],
    );

    test('builds complete snapshot from parsed message goal', () async {
      final snapshot = await PlanContextBuilder.build(
        userMessage: 'Quiero ahorrar \$50.000 para 2030',
        summary: summary,
        monthlyContribution: 200,
        asOf: asOf,
      );

      expect(snapshot['mode'], 'plan');
      expect(snapshot['data_source'], 'computed');
      expect(snapshot['current_portfolio_value'], 12000);
      expect(snapshot['monthly_contribution'], 200);
      expect(snapshot['has_complete_goal'], isTrue);

      final activeGoal = snapshot['active_goal'] as Map<String, dynamic>;
      expect(activeGoal['target_amount'], 50000);
      expect(activeGoal['target_date'], '2030-01-01');

      final projection = snapshot['projection'] as Map<String, dynamic>;
      expect(projection['months_remaining'], 43);
      expect(projection['required_monthly_savings'], closeTo(883.72, 0.01));
      expect(projection['projected_amount_at_date'], 20600);
      expect(projection['on_track'], isFalse);
      expect(projection['monthly_contribution_used'], 200);

      final milestones = snapshot['milestones'] as List<dynamic>;
      expect(milestones.length, 4);
      expect(snapshot['projection_disclaimer'], isNotEmpty);
    });

    test('prefers parsed goal over saved goal when message has new goal', () async {
      final snapshot = await PlanContextBuilder.build(
        userMessage: 'Cambiar meta a \$80.000 para 2035',
        summary: summary,
        savedGoal: (
          label: 'Retiro',
          targetAmount: 50000,
          targetDate: '2030-01-01',
        ),
        asOf: asOf,
      );

      final activeGoal = snapshot['active_goal'] as Map<String, dynamic>;
      expect(activeGoal['target_amount'], 80000);
      expect(activeGoal['target_date'], '2035-01-01');
      expect(activeGoal['label'], isNotEmpty);
    });

    test('uses saved goal when message has no parsed goal', () async {
      final snapshot = await PlanContextBuilder.build(
        userMessage: '¿Voy bien con mi meta?',
        summary: summary,
        savedGoal: (
          label: 'Retiro',
          targetAmount: 50000,
          targetDate: '2030-01-01',
        ),
        monthlyContribution: 200,
        asOf: asOf,
      );

      expect(snapshot['parsed_goal'], isNull);
      expect(snapshot['has_complete_goal'], isTrue);

      final activeGoal = snapshot['active_goal'] as Map<String, dynamic>;
      expect(activeGoal['target_amount'], 50000);
      expect(activeGoal['target_date'], '2030-01-01');
    });

    test('returns incomplete snapshot without projection when goal is partial', () async {
      final snapshot = await PlanContextBuilder.build(
        userMessage: 'Quiero ahorrar \$50.000',
        summary: summary,
        asOf: asOf,
      );

      expect(snapshot['has_complete_goal'], isFalse);
      expect(snapshot['projection'], isNull);
      expect(snapshot['milestones'], isNull);
    });
  });
}
