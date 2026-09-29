import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/company_fundamentals.dart';
import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/entities/earnings_calendar_entry.dart';
import 'package:portfolio_assistant/domain/entities/earnings_report_result.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/entities/symbol_search_result.dart';
import 'package:portfolio_assistant/domain/managers/preferences_manager.dart';
import 'package:portfolio_assistant/domain/repositories/company_fundamentals_repository.dart';
import 'package:portfolio_assistant/domain/repositories/company_news_repository.dart';
import 'package:portfolio_assistant/domain/repositories/earnings_calendar_repository.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/domain/repositories/symbol_search_repository.dart';
import 'package:portfolio_assistant/features/assistant/data/invest/yahoo_company_profile_client.dart';
import 'package:portfolio_assistant/features/assistant/data/market/company_ticker_resolver.dart';
import 'package:portfolio_assistant/features/assistant/data/market/earnings_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/fundamentals_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/data/market/news_fetcher.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';

/// Registra cada ticker pedido a Yahoo, para verificar que solo se piden
/// los datos que el modelo pidió.
class CountingQuoteRepository implements QuoteRepository {
  CountingQuoteRepository({this.failing = const {}});

  final Set<String> failing;
  final priceCalls = <String>[];
  final dailyCalls = <String>[];

  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) async {
    priceCalls.add(ticker);
    if (failing.contains(ticker)) return Left(HttpError(code: 'x'));
    return const Right(150);
  }

  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) async {
    dailyCalls.add(ticker);
    if (failing.contains(ticker)) return Left(HttpError(code: 'x'));
    final end = DateTime(2026, 9, 25);
    return Right([
      for (var i = 0; i < 400; i++)
        PriceCandle(
          date: end.subtract(Duration(days: 399 - i)),
          close: 100.0 + i / 10,
        ),
    ]);
  }

  @override
  Future<List<PriceCandle>> getIntradayCandles(String ticker) async => const [];
}

class FakeSymbolSearchRepository implements SymbolSearchRepository {
  FakeSymbolSearchRepository([this.results = const {}]);

  final Map<String, List<SymbolSearchResult>> results;
  final queries = <String>[];

  @override
  Future<Either<HttpError, List<SymbolSearchResult>>> search(
    String query,
  ) async {
    queries.add(query);
    return Right(results[query] ?? const []);
  }
}

class FakeCompanyNewsRepository implements CompanyNewsRepository {
  FakeCompanyNewsRepository({this.fail = false});

  final bool fail;
  final calls = <String>[];

  @override
  Future<Either<HttpError, List<CompanyNewsItem>>> getRecentNews(
    String ticker, {
    int limit = 3,
  }) async {
    calls.add(ticker);
    if (fail) return Left(HttpError(code: 'x'));
    return Right([
      CompanyNewsItem(
        ticker: ticker,
        headline: '$ticker headline',
        summary: 'summary',
        url: 'https://example.com',
        source: 'Reuters',
        publishedAt: DateTime.utc(2026, 9, 24),
      ),
    ]);
  }
}

class FakeEarningsCalendarRepository implements EarningsCalendarRepository {
  FakeEarningsCalendarRepository({this.next, this.latest, this.fail = false});

  final EarningsCalendarEntry? next;
  final EarningsReportResult? latest;
  final bool fail;
  final calls = <String>[];

  @override
  Future<Either<HttpError, EarningsCalendarEntry?>> getNextEarningsDate(
    String ticker,
  ) async {
    calls.add(ticker);
    return fail ? Left(HttpError(code: 'x')) : Right(next);
  }

  @override
  Future<Either<HttpError, EarningsReportResult?>> getLatestEarningsResult(
    String ticker,
  ) async => fail ? Left(HttpError(code: 'x')) : Right(latest);
}

class FakeCompanyFundamentalsRepository
    implements CompanyFundamentalsRepository {
  FakeCompanyFundamentalsRepository({this.data, this.fail = false});

  final CompanyFundamentals? data;
  final bool fail;
  final calls = <String>[];

  @override
  Future<Either<HttpError, CompanyFundamentals?>> getFundamentals(
    String ticker,
  ) async {
    calls.add(ticker);
    return fail ? Left(HttpError(code: 'x')) : Right(data);
  }
}

class FakePreferences implements PreferencesManager {
  ({String label, double targetAmount, String targetDate})? goal;
  double? monthly;

  @override
  Future<void> saveGoal({
    required String label,
    required double targetAmount,
    required String targetDate,
  }) async {
    goal = (label: label, targetAmount: targetAmount, targetDate: targetDate);
  }

  @override
  Future<({String label, double targetAmount, String targetDate})?>
  getSavedGoal() async => goal;

  @override
  Future<double?> getMonthlyContribution() async => monthly;

  @override
  Future<void> saveMonthlyContribution(double amount) async => monthly = amount;

  @override
  Future<String?> getToken() async => null;

  @override
  Future<void> saveToken({required String token}) async {}

  @override
  bool hasCompletedOnboarding() => true;

  @override
  Future<void> setOnboardingCompleted({required bool completed}) async {}
}

/// Perfiles de compañía fijos para tests (sin red). Un ticker que no está
/// en [profiles] vuelve `null`, como una falla de Yahoo.
class FakeProfileClient extends YahooCompanyProfileClient {
  FakeProfileClient([this.profiles = const {}]);

  final Map<String, YahooCompanyProfile> profiles;
  final requested = <String>[];

  @override
  Future<Map<String, YahooCompanyProfile?>> fetchProfiles(
    Iterable<String> tickers,
  ) async {
    requested.addAll(tickers);
    return {
      for (final t in tickers) t.toUpperCase(): profiles[t.toUpperCase()],
    };
  }
}

AssistantDataSources fakeDataSources({
  QuoteRepository? quotes,
  FakePreferences? preferences,
  FakeSymbolSearchRepository? symbols,
  FakeCompanyNewsRepository? news,
  FakeEarningsCalendarRepository? earnings,
  FakeCompanyFundamentalsRepository? fundamentals,
  FakeProfileClient? profiles,
}) => AssistantDataSources(
  quoteRepository: quotes ?? CountingQuoteRepository(),
  preferences: preferences ?? FakePreferences(),
  tickerResolver: CompanyTickerResolver(
    repository: symbols ?? FakeSymbolSearchRepository(),
  ),
  news: NewsFetcher(repository: news ?? FakeCompanyNewsRepository()),
  earnings: EarningsFetcher(
    repository: earnings ?? FakeEarningsCalendarRepository(),
  ),
  fundamentals: FundamentalsFetcher(
    repository: fundamentals ?? FakeCompanyFundamentalsRepository(),
  ),
  profileClient: profiles ?? FakeProfileClient(),
);

PositionValuation valuation(String ticker, {double qty = 2}) =>
    PositionValuation(
      position: Position(
        id: ticker,
        ticker: ticker,
        quantity: qty,
        purchasePrice: 100,
        purchaseDate: DateTime(2024, 1, 1),
      ),
      currentPrice: 150,
      marketValue: qty * 150,
      pnlAbsolute: qty * 50,
      pnlPercent: 50,
    );

/// Cartera de prueba: AAPL y NVDA en tenencia.
final heldSummary = PortfolioSummary(
  totalValue: 600,
  totalCostBasis: 400,
  totalPnlAbsolute: 200,
  totalPnlPercent: 50,
  valuations: [valuation('AAPL'), valuation('NVDA')],
);

// ---------------------------------------------------------------- OpenAI

/// Una respuesta guionada de Chat Completions.
Map<String, Object?> toolCallsReply(
  List<(String id, String name, Object args)> calls,
) => {
  'role': 'assistant',
  'content': null,
  'tool_calls': [
    for (final (id, name, args) in calls)
      {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': jsonEncode(args)},
      },
  ],
};

Map<String, Object?> textReply(String text) => {
  'role': 'assistant',
  'content': text,
};

/// A2UI mínimo válido para [surfaceId] con un QaAnswerText.
String a2uiAnswer(String surfaceId, String text) =>
    '{"version":"v0.9","createSurface":{"surfaceId":"$surfaceId",'
    '"catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}\n'
    '{"version":"v0.9","updateComponents":{"surfaceId":"$surfaceId",'
    '"components":[{"id":"root","component":"Column","children":["a"]},'
    '{"id":"a","component":"QaAnswerText","text":"$text"}]}}';

/// OpenAI falso a nivel HTTP: devuelve [script] en orden y guarda el body
/// de cada request — los tests afirman sobre lo que la app MANDÓ.
class ScriptedOpenAi {
  ScriptedOpenAi(this.script);

  final List<Map<String, Object?> Function(Map<String, dynamic> request)>
  script;
  final requests = <Map<String, dynamic>>[];

  late final http.Client client = MockClient((req) async {
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    requests.add(body);
    final index = requests.length - 1;
    if (index >= script.length) {
      return http.Response(
        jsonEncode({
          'error': {'message': 'unexpected request #$index'},
        }),
        500,
      );
    }
    return http.Response(
      jsonEncode({
        'id': 'chatcmpl-$index',
        'object': 'chat.completion',
        'created': 1790000000,
        'model': 'gpt-4.1-mini',
        'system_fingerprint': 'fp',
        'choices': [
          {'index': 0, 'message': script[index](body), 'finish_reason': 'stop'},
        ],
        'usage': {
          'prompt_tokens': 10,
          'completion_tokens': 5,
          'total_tokens': 15,
        },
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  List<String> rolesOf(int request) => [
    for (final m in (requests[request]['messages'] as List).cast<Map>())
      m['role'] as String,
  ];
}
