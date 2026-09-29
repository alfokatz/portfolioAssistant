import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';

abstract final class AiUsageLimits {
  static const freeMonthly = 20;
  static const premiumMonthly = 500;
  static const goldMonthly = 1000;
  /// Era 3 cuando las noticias salían de la búsqueda web de OpenAI (la
  /// fuente más cara por lejos). Desde que salen de Google News RSS (gratis)
  /// un turno de noticias cuesta lo mismo que cualquier turno con datos.
  /// Se deja el peso separado por si vuelve una fuente paga.
  static const newsQueryWeight = 1;
  static const standardQueryWeight = 1;
  static const freePositionLimit = 10;

  static int monthlyQuota(SubscriptionTier tier) => tier.monthlyQuota;
}
