import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/managers/preferences_manager.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/allocation/domain/allocation_plan.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/yahoo_company_profile_client.dart';
import 'package:portfolio_assistant/features/assistant/data/market/company_ticker_resolver.dart';
import 'package:portfolio_assistant/features/assistant/data/market/dividend_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/earnings_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/etf_holdings_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/fundamentals_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_context_client.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_provider.dart';
import 'package:portfolio_assistant/features/assistant/data/market/sec_market_fetchers.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/savings_plan_store.dart';
import 'package:portfolio_assistant/features/assistant/data/web/web_search_client.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/user_memory.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/infraestructure/repositories/gdelt_headlines_repository_impl.dart';

/// Fuentes de datos que viven toda la conversación (sus caches TTL también).
class AssistantDataSources {
  AssistantDataSources({
    required this.quoteRepository,
    required this.preferences,
    CompanyTickerResolver? tickerResolver,
    EarningsSource? earnings,
    FundamentalsSource? fundamentals,
    NewsFetcher? news,
    NewsContextClient? newsContext,
    EtfHoldingsFetcher? etfHoldings,
    YahooCompanyProfileClient? profileClient,
    DividendFetcher? dividends,
    WebSearchClient? webSearch,
    NewsProvider? newsProvider,
    NewsProviderConfig? newsProviderConfig,
  }) : _tickerResolver = tickerResolver,
       _webSearch = webSearch,
       _dividends = dividends,
       _earnings = earnings,
       _fundamentals = fundamentals,
       _news = news,
       _newsContext = newsContext,
       _etfHoldings = etfHoldings,
       _profileClient = profileClient,
       _fixedProvider = newsProvider,
       _providerConfig = newsProviderConfig ?? NewsProviderConfig.instance;

  final QuoteRepository quoteRepository;
  final PreferencesManager preferences;

  // Lazy: los clientes de Finnhub y Yahoo leen `dotenv` al construirse, y un turno
  // que no pide esos datos no debería tocarlo.
  CompanyTickerResolver? _tickerResolver;
  EarningsSource? _earnings;
  FundamentalsSource? _fundamentals;
  NewsFetcher? _news;
  NewsContextClient? _newsContext;
  final NewsProvider? _fixedProvider;
  final NewsProviderConfig _providerConfig;
  NewsProvider? _provider;
  EtfHoldingsFetcher? _etfHoldings;
  YahooCompanyProfileClient? _profileClient;
  DividendFetcher? _dividends;
  WebSearchClient? _webSearch;

  /// Planes de ahorro de la conversación (ver [SavingsPlanStore]).
  final plans = SavingsPlanStore();

  CompanyTickerResolver get tickerResolver =>
      _tickerResolver ??= CompanyTickerResolver();

  /// De dónde salen noticias, resultados y fundamentals en esta
  /// conversación (`app_config.news_provider`, leído al primer uso y fijo
  /// desde ahí: una conversación no mezcla fuentes).
  Future<NewsProvider> newsProvider() async =>
      _provider ??= _fixedProvider ?? await _providerConfig.load();

  Future<EarningsSource> earnings() async =>
      _earnings ??=
          await newsProvider() == NewsProvider.v2
              ? SecEarningsFetcher()
              : EarningsFetcher();

  Future<FundamentalsSource> fundamentals() async =>
      _fundamentals ??=
          await newsProvider() == NewsProvider.v2
              ? SecFundamentalsFetcher(quotes: quoteRepository)
              : FundamentalsFetcher();

  Future<NewsFetcher> news() async =>
      _news ??=
          await newsProvider() == NewsProvider.v2
              ? NewsFetcher(headlines: GdeltHeadlinesRepositoryImpl())
              : NewsFetcher();

  /// Contexto con citas (búsqueda web en el servidor). Solo v2.
  NewsContextClient get newsContext => _newsContext ??= NewsContextClient();
  EtfHoldingsFetcher get etfHoldings => _etfHoldings ??= EtfHoldingsFetcher();
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
    this.loadAllocationPlan,
    this.loadWatchlist,
    this.loadAppSettings,
    this.loadConnectedAccounts,
    this.loadAccountOverview,
    this.queriesLeftThisMonth,
    this.pendingRequest,
    this.loadWeeklyReport,
    this.userMemories = const [],
    this.saveMemory,
    this.deleteMemory,
    this.savedGoals = const [],
    this.saveGoal,
    this.newsProvider = NewsProvider.legacy,
    DateTime? now,
  }) : now = now ?? DateTime.now(),
       heldTickers = {
         for (final v in summary?.valuations ?? const [])
           v.position.ticker.toUpperCase(),
       };

  final SubscriptionTier tier;
  final AssistantDataSources data;

  /// Fuente de noticias/resultados/fundamentals de este turno (decide las
  /// descripciones de las tools, que viajan en la primera ronda).
  final NewsProvider newsProvider;

  bool get secData => newsProvider == NewsProvider.v2;

  /// Búsquedas de contexto de noticias en el turno (el servidor admite una).
  int newsContextCalls = 0;
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

  /// El plan de cartera guardado (get_allocation_plan); `null` si nunca
  /// armó uno. La función es `null` fuera de la app.
  final Future<AllocationPlan?> Function()? loadAllocationPlan;

  /// La lista de seguimiento (get_watchlist), ya en el formato del
  /// resultado de la tool; `null` fuera de la app.
  final Future<List<Map<String, Object?>>> Function()? loadWatchlist;

  /// Los ajustes de hoy ({clave de `AppSettingKeys`: valor}); `null` fuera
  /// de la app.
  final Future<Map<String, Object?>> Function()? loadAppSettings;

  /// Estado de cada cuenta ({`etoro`|`binance`: `connected` |
  /// `not_connected` | `reconnect_required`}); `null` fuera de la app.
  final Future<Map<String, String>> Function()? loadConnectedAccounts;

  /// La cuenta del usuario para get_app_settings: plan, consultas, cuentas
  /// conectadas (con su última actualización) y metas cumplidas; `null`
  /// fuera de la app.
  final Future<Map<String, Object?>> Function()? loadAccountOverview;

  /// Consultas a Porty que le quedan este mes (`account` del brief).
  final int? queriesLeftThisMonth;

  /// La acción que el turno anterior dejó esperando un dato (ver
  /// `AssistantTurnPolicy.pendingRequest`).
  final Map<String, Object?>? pendingRequest;

  /// El informe semanal de esta semana tal como lo ve el usuario (`null`
  /// si todavía no está); la función es `null` fuera de la app.
  final Future<Map<String, Object?>?> Function()? loadWeeklyReport;

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

  /// Las metas activas de la pestaña Metas (más nuevas primero): van en
  /// `saved_goals` del brief con la referencia de `GoalTools.refOf`.
  final List<UserGoal> savedGoals;

  /// Guarda la meta en la pestaña Metas. `null` fuera de la app.
  final Future<UserGoal> Function(GoalDraft draft)? saveGoal;

  /// Planes de una meta NUEVA calculados en este turno: el usuario todavía
  /// no vio la card ni dijo que la quiere como meta, así que save_goal no
  /// los guarda (contar "¿cuánto junto para una compu?" no es pedir una
  /// meta). Cambiar un plan que ya vio, o una meta guardada, no entra acá.
  final unconfirmedPlans = <String>{};

  /// Valor de mercado por ticker de la cartera: lo que cuenta solo para las
  /// metas (ver `UserGoal.linkedTickers`).
  Map<String, double> get holdingsByTicker {
    final map = <String, double>{};
    for (final v in summary?.valuations ?? const []) {
      final t = v.position.ticker.toUpperCase();
      map[t] = (map[t] ?? 0) + v.marketValue;
    }
    return map;
  }

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
