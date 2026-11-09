import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/models/chat_paywall.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/subscription/config/paywall_source.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';

void main() {
  test('reason, source and feature always travel together', () {
    const first = ChatPaywall(
      PaywallReason.brokerSync,
      PaywallSource.chatActionBroker,
      PlanFeature.brokerSync,
    );
    var state = const AssistantState().copyWith(paywall: first);
    expect(state.paywallReason, PaywallReason.brokerSync);
    expect(state.paywallSource, PaywallSource.chatActionBroker);
    expect(state.paywallFeature, PlanFeature.brokerSync);

    // Otro paywall sin capacidad no arrastra la del anterior.
    state = state.copyWith(
      paywall: const ChatPaywall(
        PaywallReason.quotaExceeded,
        PaywallSource.quotaZero,
      ),
    );
    expect(state.paywallReason, PaywallReason.quotaExceeded);
    expect(state.paywallFeature, isNull);

    // Otros cambios lo conservan; limpiarlo borra los tres.
    state = state.copyWith(isWaiting: true);
    expect(state.paywallSource, PaywallSource.quotaZero);
    state = state.copyWith(clearPaywall: true);
    expect(state.paywall, isNull);
    expect(state.paywallSource, isNull);
  });
}
