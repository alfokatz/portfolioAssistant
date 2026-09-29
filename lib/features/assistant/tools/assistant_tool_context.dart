import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/managers/preferences_manager.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/yahoo_company_profile_client.dart';
import 'package:portfolio_assistant/features/assistant/data/market/company_ticker_resolver.dart';
import 'package:portfolio_assistant/features/assistant/data/market/earnings_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/fundamentals_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_fetcher.dart';
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
    YahooCompanyProfileClient? profileClient,
  }) : _tickerResolver = tickerResolver,
       _earnings = earnings,
       _fundamentals = fundamentals,
       _news = news,
       _profileClient = profileClient;

  final QuoteRepository quoteRepository;
  final PreferencesManager preferences;

  // Lazy: los clientes de Finnhub leen `dotenv` al construirse, y un turno
  // que no pide esos datos no debería tocarlo.
  CompanyTickerResolver? _tickerResolver;
  EarningsFetcher? _earnings;
  FundamentalsFetcher? _fundamentals;
  NewsFetcher? _news;
  YahooCompanyProfileClient? _profileClient;

  CompanyTickerResolver get tickerResolver =>
      _tickerResolver ??= CompanyTickerResolver();
  EarningsFetcher get earnings => _earnings ??= EarningsFetcher();
  FundamentalsFetcher get fundamentals =>
      _fundamentals ??= FundamentalsFetcher();
  NewsFetcher get news => _news ??= NewsFetcher();
  YahooCompanyProfileClient get profileClient =>
      _profileClient ??= YahooCompanyProfileClient();
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
  final DateTime now;
  final Set<String> heldTickers;

  /// Paywalls que la app puede ofrecer por lo que pidió el modelo en el
  /// turno (ver `AssistantTurnPolicy.paywallFor`).
  final lockedReasons = <PaywallReason>{};

  bool get marketDataAllowed => SubscriptionPolicy.isMarketDataAllowed(tier);
  bool get premiumDataAllowed => SubscriptionPolicy.isNewsAllowed(tier);
  bool get adviceAllowed => SubscriptionPolicy.isAdviceAllowed(tier);

  String get asOf => now.toUtc().toIso8601String();

  Map<String, Object?> locked(String requiredPlan, [PaywallReason? reason]) {
    if (reason != null) lockedReasons.add(reason);
    return {'status': 'locked', 'required_plan': requiredPlan, 'as_of': asOf};
  }
}
