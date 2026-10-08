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
  /// propose_delete_position).
  portfolioActions,

  /// El análisis completo de una empresa (QaCompanyAnalysis).
  companyAnalysis,

  /// Titulares y noticias (get_news).
  news,

  /// Calendario y resultados de earnings (get_earnings).
  earnings,

  /// Valuación, márgenes, dividendo (get_fundamentals).
  fundamentals,
}

/// Un plan: qué incluye, sus límites y cómo se presenta.
class PlanSpec {
  const PlanSpec({
    required this.features,
    required this.monthlyQueries,
    required this.positionLimit,
    required this.highlights,
    this.extraMarketingKeys = const [],
  });

  final Set<PlanFeature> features;

  /// Espejo del límite del servidor (`_monthly_quota` en Supabase), que es
  /// el que manda. Cambiar uno sin el otro los desincroniza.
  final int monthlyQueries;

  /// `null` = sin tope.
  final int? positionLimit;

  /// Qué se destaca en el paywall y en la pantalla de suscripción, en orden.
  /// Solo lo NUEVO respecto del plan de abajo (el de arriba incluye todo).
  final List<PlanFeature> highlights;

  /// Textos de marketing que no corresponden a una feature con gating.
  final List<String> extraMarketingKeys;
}

/// Matriz de planes: única fuente de verdad de qué incluye cada uno.
///
/// Estructura (2026-09-30):
/// - Free    — "¿Cómo está mi cartera?"
/// - Premium — "¿Cómo está el mercado?"
/// - Gold    — "¿Qué significa, qué está pasando y por qué?"
abstract final class PlanMatrix {
  static const _free = {PlanFeature.ownPortfolio};

  static const _premium = {
    ..._free,
    PlanFeature.marketData,
    PlanFeature.benchmark,
    PlanFeature.unlimitedPositions,
    PlanFeature.investSimulation,
    PlanFeature.goals,
    PlanFeature.portfolioActions,
  };

  static const _gold = {
    ..._premium,
    PlanFeature.companyAnalysis,
    PlanFeature.news,
    PlanFeature.earnings,
    PlanFeature.fundamentals,
  };

  static const plans = <SubscriptionTier, PlanSpec>{
    SubscriptionTier.free: PlanSpec(
      features: _free,
      monthlyQueries: 20,
      positionLimit: 10,
      highlights: [PlanFeature.ownPortfolio],
    ),
    SubscriptionTier.premium: PlanSpec(
      features: _premium,
      monthlyQueries: 500,
      positionLimit: null,
      highlights: [
        PlanFeature.marketData,
        PlanFeature.investSimulation,
        PlanFeature.goals,
        PlanFeature.benchmark,
      ],
      // Se promociona desde antes pero no está implementado (solo existe el
      // switch en Configuración). Se deja hasta que negocio decida: sacarlo
      // es quitarle a Premium algo que se le prometió a quien ya paga.
      extraMarketingKeys: ['plan_feature_price_alerts'],
    ),
    SubscriptionTier.gold: PlanSpec(
      features: _gold,
      monthlyQueries: 1000,
      positionLimit: null,
      highlights: [
        PlanFeature.companyAnalysis,
        PlanFeature.news,
        PlanFeature.earnings,
        PlanFeature.fundamentals,
      ],
      // El informe semanal no es una feature con gating en la app: el
      // permiso lo decide el servidor (`claim_weekly_report`), igual que la
      // degustación.
      extraMarketingKeys: ['plan_feature_weekly_report'],
    ),
  };

  static PlanSpec of(SubscriptionTier tier) => plans[tier]!;

  static bool allows(SubscriptionTier tier, PlanFeature feature) =>
      of(tier).features.contains(feature);

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
    PlanFeature.earnings => 'plan_feature_earnings',
    PlanFeature.fundamentals => 'plan_feature_fundamentals',
  };

  /// Claves de marketing del plan, en el orden en que se muestran.
  static List<String> marketingKeys(SubscriptionTier tier) => [
    for (final f in of(tier).highlights) labelKey(f),
    ...of(tier).extraMarketingKeys,
  ];

  /// Semanas: 1 análisis Gold de cortesía para quien no tiene Gold.
  static bool hasWeeklyFreeAnalysis(SubscriptionTier tier) =>
      !allows(tier, PlanFeature.companyAnalysis);
}
