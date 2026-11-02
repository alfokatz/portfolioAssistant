// Catálogo de orígenes del paywall: únicos, con formato válido y distintos
// de los motivos (PaywallReason).
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/subscription/config/paywall_source.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';

void main() {
  group('PaywallSource', () {
    final reasonNames = PaywallReason.values.map((r) => r.name).toSet();

    test('constants are unique, valid and never a PaywallReason name', () {
      expect(
        PaywallSource.values.toSet(),
        hasLength(PaywallSource.values.length),
      );
      for (final source in PaywallSource.values) {
        expect(PaywallSource.isValid(source), isTrue, reason: source);
        expect(reasonNames, isNot(contains(source)), reason: source);
      }
    });

    test('chatTurnLocked builds snake_case sources for every feature', () {
      expect(
        PaywallSource.chatTurnLocked(PlanFeature.investSimulation),
        'chat_turn_locked_invest_simulation',
      );
      for (final feature in PlanFeature.values) {
        final source = PaywallSource.chatTurnLocked(feature);
        expect(PaywallSource.isValid(source), isTrue, reason: source);
      }
    });

    test('isValid enforces the format', () {
      expect(PaywallSource.isValid('settings'), isTrue);
      // Fallback del chat si un motivo llega sin source.
      expect(PaywallSource.isValid('chat_unattributed'), isTrue);
      expect(PaywallSource.isValid('chip_company_analysis'), isTrue);
      expect(PaywallSource.isValid('chip_companyAnalysis'), isFalse);
      expect(PaywallSource.isValid('answer_locked_news+earnings'), isFalse);
      expect(PaywallSource.isValid('ab'), isFalse);
      expect(PaywallSource.isValid('1settings'), isFalse);
      expect(PaywallSource.isValid('a' * 61), isFalse);
      expect(PaywallSource.isValid('a' * 60), isTrue);
    });

    test('snake normalizes enum names and separators', () {
      expect(PaywallSource.snake('companyAnalysis'), 'company_analysis');
      expect(
        PaywallSource.snake('fundamentals+earnings'),
        'fundamentals_earnings',
      );
      expect(PaywallSource.snake('news'), 'news');
    });
  });
}
