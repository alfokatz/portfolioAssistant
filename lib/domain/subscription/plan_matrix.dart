import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';

/// Lo que un plan puede incluir. Una feature = una decisión de negocio: el
/// gating de las tools, el paywall y la pantalla de suscripción preguntan
/// por estas, nunca por el plan directamente.
enum PlanFeature {
  /// La cartera propia: posiciones, P&L, precios de lo que tiene.
  ownPortfolio,

  /// Precios, gráficos y comparaciones de tickers que NO tiene.
  marketData,

  /// Comparación de la cartera contra el S&P 500 (home).
  benchmark,

  /// Sin tope de posiciones cargadas.
  unlimitedPositions,

  /// Simulaciones educativas de inversión (get_invest_candidates).
  investSimulation,

  /// Metas de ahorro y proyecciones (get_goal_projection, save_goal).
  goals,

  /// Registrar operaciones desde el chat (compras, ventas, borrados) con
  /// confirmación del usuario (propose_buy, propose_sell,
  /// propose_delete_position). Desde 2026-11-05 está en todos los planes; el
  /// tope de posiciones sigue rigiendo las compras de tickers nuevos.
  portfolioActions,

  /// El análisis completo de una empresa (QaCompanyAnalysis).
  companyAnalysis,

  /// Titulares y noticias (get_news).
  news,

  /// Noticias y "por qué se movió" SOLO de tickers en cartera (get_news).
  /// Está en Premium (y por herencia en Gold). Ver [PlanMatrix.allowsNewsFor].
  heldNews,

  /// Calendario y resultados de earnings (get_earnings).
  earnings,

  /// Valuación, márgenes, dividendo (get_fundamentals).
  fundamentals,

  /// Conectar la cuenta de eToro (solo lectura) y que la cartera se
  /// actualice sola. El servidor (etoro-sync) también lo exige.
  brokerSync,

  /// Conectar más de un bróker por SnapTrade (Premium conecta uno). El
  /// servidor (snaptrade-sync) también lo exige.
  multiBrokerSync,

  /// "Actualizar ahora" de los brókers conectados por SnapTrade (cada una
  /// se paga; el servidor además la habilita y le pone cupo diario).
  brokerManualRefresh,

  /// Plan de cartera: asignación objetivo, desvío y cómo repartir el
  /// próximo aporte. La base también lo exige (`allocation_plans`).
  allocationPlan,
}

/// Un plan: qué incluye, sus límites y cómo se presenta.
class PlanSpec {
  const PlanSpec({
    required this.features,
    required this.monthlyQueries,
    required this.positionLimit,
    required this.priceAlertLimit,
    required this.watchlistLimit,
    required this.highlights,
    this.leadingMarketingKeys = const [],
    this.extraMarketingKeys = const [],
    this.quotaNudgeAtRemaining,
    this.marketDataTastesPerMonth = 0,
  });

  final Set<PlanFeature> features;

  /// Espejo del límite del servidor (`_monthly_quota` en Supabase), que es
  /// el que manda. Cambiar uno sin el otro los desincroniza.
  final int monthlyQueries;

  /// `null` = sin tope.
  final int? positionLimit;

  /// Alertas de precio activas a la vez. Espejo de `plan_limits.price_alerts`
  /// en Supabase, que es el que manda (un trigger corta con
  /// `alert_limit_reached`).
  final int priceAlertLimit;

  /// Tickers en la lista de seguimiento. Espejo de `plan_limits.watchlist`
  /// en Supabase, que es el que manda (`watchlist_limit_reached`).
  final int watchlistLimit;

  /// Qué se destaca en el paywall y en la pantalla de suscripción, en orden.
  /// Solo lo NUEVO respecto del plan de abajo (el de arriba incluye todo).
  final List<PlanFeature> highlights;

  /// Textos de marketing que van ANTES de los highlights (p. ej. el informe
  /// semanal en Gold, que lidera su promesa).
  final List<String> leadingMarketingKeys;

  /// Textos de marketing que no corresponden a una feature con gating.
  final List<String> extraMarketingKeys;

  /// Avisar en el chat cuando quedan estas consultas del mes. null = no
  /// avisar.
  final int? quotaNudgeAtRemaining;

  /// Consultas de mercado (tickers que no tiene) de regalo por mes, si el plan
  /// no incluye PlanFeature.marketData. Espejo de
  /// plan_limits.market_tastes_per_month (el servidor manda). El chat
  /// pregunta `> 0`, nunca por el plan.
  final int marketDataTastesPerMonth;
}

/// Matriz de planes: única fuente de verdad de qué incluye cada uno.
///
/// Estructura (2026-11-05):
/// - Free    — la cartera completa, operaciones por chat y 3 tickers.
/// - Premium — tu plata ordenada y al día, y por qué se movió lo tuyo.
/// - Gold    — Porty te explica cualquier empresa y qué pasó.
abstract final class PlanMatrix {
  static const _free = {PlanFeature.ownPortfolio, PlanFeature.portfolioActions};

  static const _premium = {
    ..._free,
    PlanFeature.marketData,
    PlanFeature.benchmark,
    PlanFeature.unlimitedPositions,
    PlanFeature.investSimulation,
    PlanFeature.goals,
    PlanFeature.heldNews,
    PlanFeature.brokerSync,
    PlanFeature.allocationPlan,
  };

  static const _gold = {
    ..._premium,
    PlanFeature.companyAnalysis,
    PlanFeature.news,
    PlanFeature.earnings,
    PlanFeature.fundamentals,
    PlanFeature.multiBrokerSync,
    PlanFeature.brokerManualRefresh,
  };

  static const plans = <SubscriptionTier, PlanSpec>{
    SubscriptionTier.free: PlanSpec(
      features: _free,
      monthlyQueries: 20,
      positionLimit: 10,
      // Una, para conocer la feature (decisión D1 del plan de push).
      priceAlertLimit: 1,
      // Seguir 3 tickers que no tiene (decisión 2026-11-05). Espejo de
      // plan_limits.watchlist.
      watchlistLimit: 3,
      highlights: [PlanFeature.ownPortfolio],
      quotaNudgeAtRemaining: 5,
      marketDataTastesPerMonth: 3,
    ),
    SubscriptionTier.premium: PlanSpec(
      features: _premium,
      monthlyQueries: 500,
      positionLimit: null,
      priceAlertLimit: 20,
      watchlistLimit: 30,
      // Simulaciones, benchmark y alertas siguen incluidos, pero no se
      // destacan en el marketing.
      highlights: [
        PlanFeature.brokerSync,
        PlanFeature.unlimitedPositions,
        PlanFeature.heldNews,
        PlanFeature.allocationPlan,
        PlanFeature.goals,
        PlanFeature.marketData,
      ],
    ),
    SubscriptionTier.gold: PlanSpec(
      features: _gold,
      monthlyQueries: 1000,
      positionLimit: null,
      priceAlertLimit: 50,
      watchlistLimit: 100,
      // El informe semanal no es una feature con gating en la app: el
      // permiso lo decide el servidor (`claim_weekly_report`), igual que la
      // degustación. Lidera la lista.
      leadingMarketingKeys: ['plan_feature_weekly_report'],
      highlights: [
        PlanFeature.multiBrokerSync,
        PlanFeature.companyAnalysis,
        PlanFeature.news,
        PlanFeature.earnings,
      ],
    ),
  };

  /// El plan siguiente (para "Con Premium tenés 500"). null en Gold.
  static SubscriptionTier? nextTier(SubscriptionTier tier) {
    final i = SubscriptionTier.values.indexOf(tier);
    return i + 1 < SubscriptionTier.values.length
        ? SubscriptionTier.values[i + 1]
        : null;
  }

  static PlanSpec of(SubscriptionTier tier) => plans[tier]!;

  static bool allows(SubscriptionTier tier, PlanFeature feature) =>
      of(tier).features.contains(feature);

  /// Noticias de un ticker: todas con `news` (Gold) o, con `heldNews`
  /// (Premium), solo las de tickers que el usuario tiene en cartera.
  static bool allowsNewsFor(SubscriptionTier tier, {required bool held}) =>
      allows(tier, PlanFeature.news) ||
      (held && allows(tier, PlanFeature.heldNews));

  /// El plan más barato que incluye [feature] (para "incluido en X").
  static SubscriptionTier minimumTier(PlanFeature feature) {
    for (final tier in SubscriptionTier.values) {
      if (allows(tier, feature)) return tier;
    }
    return SubscriptionTier.gold;
  }

  /// Texto de una feature en el paywall / suscripción (clave de traducción).
  static String labelKey(PlanFeature feature) => switch (feature) {
    PlanFeature.ownPortfolio => 'plan_feature_own_portfolio',
    PlanFeature.marketData => 'plan_feature_market_data',
    PlanFeature.benchmark => 'plan_feature_benchmark',
    PlanFeature.unlimitedPositions => 'plan_feature_unlimited_positions',
    PlanFeature.investSimulation => 'plan_feature_invest_simulation',
    PlanFeature.goals => 'plan_feature_goals',
    PlanFeature.portfolioActions => 'plan_feature_portfolio_actions',
    PlanFeature.companyAnalysis => 'plan_feature_company_analysis',
    PlanFeature.news => 'plan_feature_news',
    PlanFeature.heldNews => 'plan_feature_held_news',
    PlanFeature.earnings => 'plan_feature_earnings',
    PlanFeature.fundamentals => 'plan_feature_fundamentals',
    PlanFeature.brokerSync => 'plan_feature_broker_sync',
    PlanFeature.multiBrokerSync => 'plan_feature_multi_broker_sync',
    PlanFeature.brokerManualRefresh => 'plan_feature_broker_manual_refresh',
    PlanFeature.allocationPlan => 'plan_feature_allocation_plan',
  };

  /// Claves de marketing del plan, en el orden en que se muestran.
  static List<String> marketingKeys(SubscriptionTier tier) => [
    ...of(tier).leadingMarketingKeys,
    for (final f in of(tier).highlights) labelKey(f),
    ...of(tier).extraMarketingKeys,
  ];

  /// Semanas: 1 análisis Gold de cortesía para quien no tiene Gold.
  static bool hasWeeklyFreeAnalysis(SubscriptionTier tier) =>
      !allows(tier, PlanFeature.companyAnalysis);
}
