import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';

/// Un paywall que pide el chat: la hoja ([reason]), desde dónde se abrió
/// ([source], ver `PaywallSource`) y qué capacidad faltó ([feature]). Viaja
/// como el `reason` de `TurnAbortedException` y queda en
/// `AssistantState.paywall` hasta que la pantalla lo muestra. Los tres van
/// siempre juntos: por eso son un solo valor.
class ChatPaywall {
  const ChatPaywall(this.reason, this.source, [this.feature]);

  final PaywallReason reason;
  final String source;

  /// La capacidad que el plan no incluyó: va como `locked_feature` en
  /// `paywall_viewed` (ver `SubscriptionPaywallSheet.show`).
  final PlanFeature? feature;

  @override
  bool operator ==(Object other) =>
      other is ChatPaywall &&
      other.reason == reason &&
      other.source == source &&
      other.feature == feature;

  @override
  int get hashCode => Object.hash(reason, source, feature);

  @override
  String toString() => 'ChatPaywall(${reason.name}, $source, ${feature?.name})';
}
