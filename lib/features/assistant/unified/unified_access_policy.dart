import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/unified/message_needs.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';

/// Gating del pipeline unificado: depende del DATO que el mensaje necesita,
/// no de un modo. Se evalúa sobre [MessageNeeds], antes de pedir nada
/// externo y antes de llamar al modelo.
///
/// - La propia cartera (incluidos los tickers que el usuario tiene) y las
///   preguntas conceptuales: siempre disponibles.
/// - Datos de mercado de tickers que NO tiene (incluido el proxy de
///   mercado): el mismo nivel que antes tenía el modo Explore.
/// - Pedido explícito de noticias: el mismo nivel que antes (Gold).
abstract final class UnifiedAccessPolicy {
  static bool hasMarketData(SubscriptionTier tier) =>
      SubscriptionPolicy.isModeAllowed(tier, AssistantMode.explore);

  static bool hasNews(SubscriptionTier tier) =>
      SubscriptionPolicy.isNewsAllowed(tier);

  /// `null` si el plan cubre todo lo que el mensaje necesita.
  static PaywallReason? paywallFor(MessageNeeds needs, SubscriptionTier tier) {
    if (needs.needsMarketData && !hasMarketData(tier)) {
      return PaywallReason.marketDataLocked;
    }
    if (needs.isExplicitNewsRequest && !hasNews(tier)) {
      return PaywallReason.newsRequiresGold;
    }
    return null;
  }
}
