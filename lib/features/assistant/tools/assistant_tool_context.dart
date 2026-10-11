import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/managers/preferences_manager.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/yahoo_company_profile_client.dart';
import 'package:portfolio_assistant/features/assistant/data/market/company_ticker_resolver.dart';
import 'package:portfolio_assistant/features/assistant/data/market/dividend_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/earnings_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/etf_holdings_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/fundamentals_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_store.dart';
import 'package:portfolio_assistant/features/assistant/data/web/web_search_client.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/user_memory.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';

/// Fuentes de datos que viven toda la conversación (sus caches TTL también).
class AssistantDataSources {
  AssistantDataSources({
    required this.quoteRepository,
    required this.preferences,
    CompanyTickerResolver? tickerResolver,
    EarningsFetcher? earnings,
    FundamentalsFetcher? fundamentals,
    NewsFetcher? news,
    EtfHoldingsFetcher? etfHoldings,
    YahooCompanyProfileClient? profileClient,
    DividendFetcher? dividends,
    WebSearchClient? webSearch,
  }) : _tickerResolver = tickerResolver,
       _webSearch = webSearch,
       _dividends = dividends,
       _earnings = earnings,
       _fundamentals = fundamentals,
       _news = news,
       _etfHoldings = etfHoldings,
       _profileClient = profileClient;

  final QuoteRepository quoteRepository;
  final PreferencesManager preferences;

  // Lazy: los clientes de Finnhub y Yahoo leen `dotenv` al construirse, y un turno
  // que no pide esos datos no debería tocarlo.
  CompanyTickerResolver? _tickerResolver;
  EarningsFetcher? _earnings;
  FundamentalsFetcher? _fundamentals;
  NewsFetcher? _news;
  EtfHoldingsFetcher? _etfHoldings;
  YahooCompanyProfileClient? _profileClient;
  DividendFetcher? _dividends;
  WebSearchClient? _webSearch;

  /// Planes de ahorro de la conversación (ver [SavingsPlanStore]).
  final plans = SavingsPlanStore();

  CompanyTickerResolver get tickerResolver =>
      _tickerResolver ??= CompanyTickerResolver();
  EarningsFetcher get earnings => _earnings ??= EarningsFetcher();
  FundamentalsFetcher get fundamentals =>
      _fundamentals ??= FundamentalsFetcher();
  NewsFetcher get news => _news ??= NewsFetcher();
  EtfHoldingsFetcher get etfHoldings =>
      _etfHoldings ??= EtfHoldingsFetcher();
  YahooCompanyProfileClient get profileClient =>
      _profileClient ??= YahooCompanyProfileClient();
  DividendFetcher get dividends => _dividends ??= DividendFetcher();
  WebSearchClient get webSearch => _webSearch ??= WebSearchClient();
}

/// Lo que las tools necesitan saber del usuario en ESTE turno. El plan se
/// hace cumplir acá, al ejecutar cada tool — el modelo puede pedir lo que
/// quiera, pero un dato fuera del plan vuelve como `status: locked`.
class AssistantToolContext {
  AssistantToolContext({
    required this.tier,
    required this.data,
    this.summary,
    this.history = const [],
    this.closedPositions = const [],
    this.loadInvestorProfile,
    this.investorProfile,
    this.actionsThisConversation = const [],
    this.loadPriceAlerts,
    this.userMemories = const [],
    this.saveMemory,
    this.deleteMemory,
    DateTime? now,
  }) : now = now ?? DateTime.now(),
       heldTickers = {
         for (final v in summary?.valuations ?? const [])
           v.position.ticker.toUpperCase(),
       };

  final SubscriptionTier tier;
  final AssistantDataSources data;
  final PortfolioSummary? summary;
  final List<PortfolioHistoryPoint> history;
  final List<ClosedPosition> closedPositions;
  final Future<InvestorProfile?> Function()? loadInvestorProfile;

  /// El perfil ya cargado al empezar el turno (para PORTFOLIO_BRIEF); `null`
  /// si no lo completó o no se pudo leer.
  final InvestorProfile? investorProfile;

  /// Operaciones propuestas en esta conversación que el usuario ya confirmó,
  /// canceló o está guardando (ver `ActionProposalProgress.toBrief`).
  final List<Map<String, Object?>> actionsThisConversation;

  /// Las alertas de precio del usuario (list_price_alerts), ya en el
  /// formato del resultado de la tool; `null` fuera de la app.
  final Future<List<Map<String, Object?>>> Function()? loadPriceAlerts;

  /// Lo que Porty sabe del usuario al empezar el turno (más recientes
  /// primero): va en `user_memory` del brief, con la referencia de
  /// `MemoryTools.refOf`.
  final List<UserMemory> userMemories;

  /// Guarda un dato nuevo, o reemplaza [replacesId]. `null` fuera de la app.
  final Future<UserMemory> Function(
    String content,
    UserMemoryCategory category, {
    String? replacesId,
  })?
  saveMemory;
  final Future<void> Function(String id)? deleteMemory;

  /// Lo que Porty anotó en este turno: la app lo muestra debajo de la
  /// respuesta ("Porty anotó: …").
  final rememberedFacts = <String>[];
  final DateTime now;
  final Set<String> heldTickers;

  /// Paywalls que la app puede ofrecer por lo que pidió el modelo en el
  /// turno (ver `AssistantTurnPolicy.paywallFor`).
  final lockedReasons = <PaywallReason>{};

  bool allows(PlanFeature feature) => SubscriptionPolicy.allows(tier, feature);

  bool get marketDataAllowed => allows(PlanFeature.marketData);

  /// El plan más barato que incluye [feature], como lo nombra la tool
  /// ("premium" / "gold") en `required_plan`.
  String requiredPlanFor(PlanFeature feature) =>
      PlanMatrix.minimumTier(feature).name;

  String get asOf => now.toUtc().toIso8601String();

  /// Ticker del análisis de cortesía de la semana, si este turno lo usa
  /// (ver `WeeklyFreeAnalysisGrant`). Mientras esté fijado, las fuentes de
  /// Gold de ESE ticker responden aunque el plan no las incluya.
  String? courtesyTicker;

  /// Si alguna tool sirvió datos de Gold gracias a la cortesía.
  bool courtesyServed = false;

  /// Gating único de las fuentes de datos: el plan la incluye, o es el
  /// análisis de cortesía de [courtesyTicker]. Devuelve `null` si pasa, o
  /// el resultado `locked` a devolverle al modelo.
  Map<String, Object?>? gate(PlanFeature feature, List<String> tickers) {
    if (allows(feature)) return null;
    final grant = courtesyTicker;
    if (grant != null &&
        tickers.isNotEmpty &&
        tickers.every((t) => t.toUpperCase() == grant)) {
      courtesyServed = true;
      return null;
    }
    return lockedFeature(feature);
  }

  /// `locked` con el plan mínimo y el paywall que corresponden a [feature].
  Map<String, Object?> lockedFeature(PlanFeature feature) {
    final plan = PlanMatrix.minimumTier(feature);
    final reason = switch (feature) {
      PlanFeature.marketData => PaywallReason.marketDataLocked,
      _ when plan == SubscriptionTier.gold => PaywallReason.goldRequired,
      _ => PaywallReason.modeLocked,
    };
    return locked(plan.name, reason);
  }

  /// Marca un resultado servido por la cortesía, para que la card lo diga.
  Map<String, Object?> courtesyTag(Map<String, Object?> result) =>
      courtesyTicker != null && !allowsAnyGoldData
          ? {...result, 'courtesy': 'weekly_free_analysis'}
          : result;

  bool get allowsAnyGoldData => allows(PlanFeature.companyAnalysis);

  Map<String, Object?> locked(String requiredPlan, [PaywallReason? reason]) {
    if (reason != null) lockedReasons.add(reason);
    return {'status': 'locked', 'required_plan': requiredPlan, 'as_of': asOf};
  }
}
