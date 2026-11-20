import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';

abstract final class AiUsageLimits {
  static int get freeMonthly => PlanMatrix.of(SubscriptionTier.free).monthlyQueries;
  static int get premiumMonthly =>
      PlanMatrix.of(SubscriptionTier.premium).monthlyQueries;
  static int get goldMonthly => PlanMatrix.of(SubscriptionTier.gold).monthlyQueries;
  /// Era 3 cuando las noticias salían de la búsqueda web de OpenAI (la
  /// fuente más cara por lejos). Desde que salen de Google News RSS (gratis)
  /// un turno de noticias cuesta lo mismo que cualquier turno con datos.
  /// Se deja el peso separado por si vuelve una fuente paga.
  static const newsQueryWeight = 1;
  static const standardQueryWeight = 1;
  static int get freePositionLimit =>
      PlanMatrix.of(SubscriptionTier.free).positionLimit!;

  static int monthlyQuota(SubscriptionTier tier) => tier.monthlyQuota;
}
