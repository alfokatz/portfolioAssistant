import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/subscription_status.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/closed_position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/subscription_repository.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_tracker.dart';
import 'package:portfolio_assistant/domain/use_cases/get_benchmark_comparison_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/delete_positions_by_ticker_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_history_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_summary_use_case.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_price_chart.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/company_ticker_resolver.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_earnings_enricher.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/explore_news_enricher.dart';
import 'package:portfolio_assistant/features/assistant/providers/assistant_provider.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_assistant_catalog.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_assistant_flag.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_pipeline_deps.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/portfolio_qa_assistant_surface.dart';
import 'package:portfolio_assistant/features/genui_core/utils/a2ui_controller_dispatch.dart';
import 'package:portfolio_assistant/features/genui_core/utils/a2ui_response_normalizer.dart';
import 'package:portfolio_assistant/features/subscription/providers/revenue_cat_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/genui_test_helpers.dart';
import 'unified_test_fakes.dart';

/// Punta a punta de `submitMessage` con el flag prendido: flag → router
/// (solo separa Invest/Plan) → `MessageNeedsAnalyzer` → gating por dato →
/// `UnifiedContextBuilder` → servicio unificado → surface GenUI renderizada.
///
/// Lo ÚNICO reemplazado es la llamada HTTP a OpenAI (`handleSend`): el
/// armado real del mensaje (encabezado ASSISTANT_SNAPSHOT + snapshot +
/// SURFACE_ID) corre igual que en producción, y la respuesta canned del
/// "modelo" entra por el mismo normalizador + dispatch al controller que
/// usa el servicio real. Todo lo externo (Yahoo, Finnhub, Supabase,
/// RevenueCat) son fakes.
class _FakeUnifiedService extends AssistantOpenAiService {
  _FakeUnifiedService({required this.respond})
    : super(
        apiKey: 'test',
        model: 'test',
        systemPrompt: 'test',
        catalog: UnifiedAssistantCatalog.build(),
        snapshotLabel: 'ASSISTANT_SNAPSHOT',
      );

  /// Respuesta canned del "modelo" (lista A2UI de componentes) según la
  /// pregunta. `null` → simula una generación rota.
  final String? Function(String question) respond;

  final sentBodies = <String>[];

  Map<String, dynamic> snapshotOf(int turn) {
    final body = sentBodies[turn];
    final start = body.indexOf('{');
    final end = body.indexOf('\n\nPREGUNTA DEL USUARIO');
    return jsonDecode(body.substring(start, end).trim())
        as Map<String, dynamic>;
  }

  @override
  Future<void> handleSend(ChatMessage message, {String? surfaceId}) async {
    sentBodies.add(message.text);
    final question =
        message.text.split('PREGUNTA DEL USUARIO:\n')[1].split('\n').first;
    final raw = respond(question);
    if (raw == null) throw const FormatException('respuesta sin JSON válido');
    A2uiControllerDispatch.dispatchNormalized(
      controller,
      A2uiResponseNormalizer.normalize(raw, surfaceId: surfaceId!),
    );
  }
}

class _FakeSubscriptionRepository implements SubscriptionRepository {
  _FakeSubscriptionRepository(this.tier);

  final SubscriptionTier tier;
  final consumed = <int>[];

  @override
  Future<SubscriptionStatus> fetchStatus() async => SubscriptionStatus(
    tier: tier,
    queriesUsed: 0,
    queriesLimit: 1000,
    month: '2026-09',
  );

  @override
  Future<bool> consumeQuota(int weight) async {
    consumed.add(weight);
    return true;
  }
}

class _FakeAuth implements SupabaseAuthService {
  @override
  Session? get currentSession => Session(
    accessToken: 'token',
    tokenType: 'bearer',
    user: const User(
      id: 'user',
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Unused {
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected call: ${invocation.memberName}');
}

class _UnusedRevenueCat extends _Unused implements RevenueCatService {}

class _UnusedSummaryUseCase extends _Unused
    implements GetPortfolioSummaryUseCase {}

class _UnusedHistoryUseCase extends _Unused
    implements GetPortfolioHistoryUseCase {}

class _UnusedBenchmarkUseCase extends _Unused
    implements GetBenchmarkComparisonUseCase {}

class _UnusedDeleteUseCase extends _Unused
    implements DeletePositionsByTickerUseCase {}

class _UnusedClosedRepository extends _Unused
    implements ClosedPositionRepository {}

class _NoClosedPositions extends GetClosedPositionsUseCase {
  _NoClosedPositions() : super(repository: _UnusedClosedRepository());

  @override
  Future<Either<HttpError, List<ClosedPosition>>> call({void params}) async =>
      const Right([]);
}

/// Home ya cargada con la cartera de prueba (AAPL + NVDA).
class _LoadedHome extends HomeProvider {
  _LoadedHome(Ref ref)
    : super(
        ref: ref,
        getPortfolioSummaryUseCase: _UnusedSummaryUseCase(),
        getPortfolioHistoryUseCase: _UnusedHistoryUseCase(),
        getBenchmarkComparisonUseCase: _UnusedBenchmarkUseCase(),
        deletePositionsByTickerUseCase: _UnusedDeleteUseCase(),
        getClosedPositionsUseCase: _NoClosedPositions(),
      ) {
    state = HomeState(summary: heldSummary);
  }
}

class _Harness {
  _Harness({
    required this.prefs,
    required SubscriptionTier tier,
    Set<String> failingTickers = const {},
    String? Function(String question)? respond,
  }) : subscriptionRepo = _FakeSubscriptionRepository(tier),
       quotes = CountingQuoteRepository(failing: failingTickers) {
    service = _FakeUnifiedService(respond: respond ?? _defaultResponse);
    final tracker = AiUsageTracker(repository: subscriptionRepo);
    container = ProviderContainer(
      overrides: [
        // Igual que `main()`: sin esto, cualquier lectura de preferencias
        // (ej. el setting de haptics de QaAnswerText) tira UnimplementedError.
        sharedPreferencesProvider.overrideWithValue(prefs),
        homeProvider.overrideWith((ref) => _LoadedHome(ref)),
        getClosedPositionsUseCaseProvider.overrideWithValue(
          _NoClosedPositions(),
        ),
        quoteRepositoryProvider.overrideWithValue(quotes),
        aiUsageTrackerProvider.overrideWithValue(tracker),
        revenueCatServiceProvider.overrideWithValue(_UnusedRevenueCat()),
        subscriptionProvider.overrideWith(
          (ref) => SubscriptionNotifier(
            tracker: tracker,
            authService: _FakeAuth(),
            revenueCat: _UnusedRevenueCat(),
          ),
        ),
        unifiedPipelineDepsProvider.overrideWithValue(
          UnifiedPipelineDeps(
            createService: () {
              servicesCreated++;
              return service;
            },
            createTickerResolver:
                () => CompanyTickerResolver(
                  repository: FakeSymbolSearchRepository(const {}),
                ),
            createNewsEnricher: () => ExploreNewsEnricher(newsRepository: news),
            createEarningsEnricher:
                () => ExploreEarningsEnricher(
                  earningsRepository: FakeEarningsCalendarRepository(),
                ),
          ),
        ),
      ],
    );
    // autoDispose: mantener vivo el provider durante todo el test.
    container.listen(assistantProvider(const AssistantArgs()), (_, _) {});
  }

  final SharedPreferences prefs;
  final _FakeSubscriptionRepository subscriptionRepo;
  final CountingQuoteRepository quotes;
  final news = FakeCompanyNewsRepository();
  late final _FakeUnifiedService service;
  late final ProviderContainer container;
  var servicesCreated = 0;

  AssistantProvider get notifier =>
      container.read(assistantProvider(const AssistantArgs()).notifier);
  AssistantState get state =>
      container.read(assistantProvider(const AssistantArgs()));

  static String _defaultResponse(String question) => jsonEncode([
    {
      'id': 'answer',
      'component': 'QaAnswerText',
      'text': 'Respuesta a: $question',
    },
  ]);

  void dispose() => container.dispose();
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    UnifiedAssistantFlag.debugOverride = true;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() => UnifiedAssistantFlag.debugOverride = null);

  _Harness harness({
    required SubscriptionTier tier,
    Set<String> failingTickers = const {},
    String? Function(String question)? respond,
  }) {
    final h = _Harness(
      prefs: prefs,
      tier: tier,
      failingTickers: failingTickers,
      respond: respond,
    );
    addTearDown(h.dispose);
    return h;
  }

  test(
    'the production factory builds the unified prompt (not a mode prompt)',
    () {
      dotenv.testLoad(fileInput: 'OPENAI_API_KEY=test\nOPENAI_MODEL=test');
      final service =
          ProviderContainer().read(unifiedPipelineDepsProvider).createService();
      addTearDown(service.dispose);
      expect(service.snapshotLabel, 'ASSISTANT_SNAPSHOT');
      expect(service.systemPrompt, contains('UNIFIED ASSISTANT RULES'));
      expect(service.systemPrompt, contains('QaPositionsSnapshot'));
      for (final modePrompt in const [
        'EXPLORE MODE RULES',
        'LEARN MODE RULES',
        'PORTFOLIO Q&A RULES',
      ]) {
        expect(service.systemPrompt, isNot(contains(modePrompt)));
      }
    },
  );

  testWidgets(
    'free user, held ticker: no paywall, snapshot built from needs, one unified '
    'service, surface resolves and renders the chart',
    (tester) async {
      // El harness (servicio, controller, streams) se crea con timers reales:
      // creado dentro de la zona fake-async de testWidgets, sus eventos no
      // llegarían a `sendAndWait` mientras el envío corre en `runAsync`.
      final h =
          (await tester.runAsync(() async {
            final h = harness(
              tier: SubscriptionTier.free,
              respond:
                  (_) => jsonEncode([
                    {
                      'id': 'answer',
                      'component': 'QaAnswerText',
                      'text': 'AAPL cotiza a 150 dólares.',
                    },
                    {
                      'id': 'chart',
                      'component': 'QaPriceChart',
                      'ticker': 'AAPL',
                      'initialRange': '1M',
                      'currentPrice': 150,
                    },
                  ]),
            );
            await h.notifier.submitMessage('¿A cuánto está AAPL?');
            return h;
          }))!;

      expect(h.state.paywallReason, isNull);
      expect(h.state.error, isNull);
      expect(h.servicesCreated, 1);

      // Mensaje real enviado al modelo.
      final body = h.service.sentBodies.single;
      expect(body, startsWith('ASSISTANT_SNAPSHOT (usar solo estos datos):'));
      expect(
        body,
        contains(
          'SURFACE_ID (usar exactamente en createSurface y updateComponents):\nassistant_unified_0',
        ),
      );
      final snapshot = h.service.snapshotOf(0);
      expect(snapshot['access'], {'market_data': false, 'news': false});
      expect((snapshot['tickers'] as Map)['AAPL']['held'], isTrue);
      expect((snapshot['portfolio'] as Map)['has_positions'], isTrue);

      // Estado del chat.
      final reply = h.state.messages.last;
      expect(reply.role, PortfolioQaRole.assistant);
      expect(reply.surfaceId, 'assistant_unified_0');
      expect(reply.isStreaming, isFalse);
      expect(reply.isFallback, isFalse);
      expect(reply.engineMode, isNull);
      expect(reply.subjectTickers, ['AAPL']);
      expect(identical(h.notifier.serviceForMessage(reply), h.service), isTrue);
      expect(h.subscriptionRepo.consumed, [1]);

      // Surface GenUI renderizada desde la conversación del servicio.
      await tester.binding.setSurfaceSize(genuiTestViewportSize);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: genuiTestApp(
            child: SingleChildScrollView(
              child: PortfolioQaAssistantSurface(
                surfaceId: reply.surfaceId!,
                surfaceContext: h.service.controller.contextFor(
                  reply.surfaceId!,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.textContaining('AAPL cotiza a 150 dólares.'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is PriceLinePainter,
        ),
        findsOneWidget,
      );
    },
  );

  test(
    'free user, ticker they do not hold: marketDataLocked BEFORE any fetch or model call',
    () async {
      final h = harness(tier: SubscriptionTier.free);
      final before = h.state.messages.length;

      await h.notifier.submitMessage('¿A cuánto está TSLA?');

      expect(h.state.paywallReason, PaywallReason.marketDataLocked);
      expect(h.quotes.priceCalls, isEmpty);
      expect(h.service.sentBodies, isEmpty);
      expect(h.state.messages, hasLength(before));
      expect(h.subscriptionRepo.consumed, isEmpty);
    },
  );

  test(
    'free user, "¿qué es un ETF, como SPY?": no paywall, no prices, conceptual turn',
    () async {
      final h = harness(tier: SubscriptionTier.free);

      await h.notifier.submitMessage('¿Qué es un ETF, como SPY?');

      expect(h.state.paywallReason, isNull);
      expect(h.quotes.priceCalls, isEmpty);
      expect(h.quotes.dailyCalls, isEmpty);
      expect(h.service.snapshotOf(0)['tickers'], isEmpty);
      expect(h.state.messages.last.subjectTickers, isEmpty);
    },
  );

  test(
    'gold user, follow-up "¿y las noticias?": ticker comes from the stored turn, '
    'news fetched for it, same single service/history, explicit news weighs 3',
    () async {
      final h = harness(tier: SubscriptionTier.gold);

      await h.notifier.submitMessage('¿A cuánto está AAPL?');
      await h.notifier.submitMessage('¿Y las noticias?');

      expect(h.servicesCreated, 1);
      expect(h.service.sentBodies, hasLength(2));
      final second = h.service.snapshotOf(1);
      expect((second['tickers'] as Map).keys, ['AAPL']);
      expect(second['news_enrichment'], 'ok');
      expect(h.news.calls, ['AAPL']);
      expect(h.state.messages.last.surfaceId, 'assistant_unified_1');
      expect(h.subscriptionRepo.consumed, [1, 3]);
    },
  );

  test('every requested ticker failed: the only pre-model cut', () async {
    final h = harness(tier: SubscriptionTier.gold, failingTickers: {'TSLA'});

    await h.notifier.submitMessage('¿A cuánto está TSLA?');

    expect(h.state.error, isNotNull);
    expect(h.service.sentBodies, isEmpty);
  });

  test(
    'a broken generation falls back to text, keeping the surfaceId for a late retry',
    () async {
      final h = harness(tier: SubscriptionTier.free, respond: (_) => null);

      await h.notifier.submitMessage('¿Cómo está mi cartera?');

      final reply = h.state.messages.last;
      expect(reply.isFallback, isTrue);
      expect(reply.isStreaming, isFalse);
      expect(reply.surfaceId, 'assistant_unified_0');
      expect(h.state.error, isNull);
    },
  );

  test(
    'Invest/Plan still go through their own pipeline (mode gating), never the unified one',
    () async {
      final h = harness(tier: SubscriptionTier.free);

      await h.notifier.submitMessage('Tengo \$500 para invertir');

      expect(h.state.paywallReason, PaywallReason.modeLocked);
      expect(h.servicesCreated, 0);
    },
  );

  test('flag OFF: the mode pipeline answers exactly as before', () async {
    UnifiedAssistantFlag.debugOverride = false;
    final h = harness(tier: SubscriptionTier.free);

    await h.notifier.submitMessage('¿Cuál es el precio de TSLA?');

    expect(h.state.paywallReason, PaywallReason.modeLocked);
    expect(h.servicesCreated, 0);
  });
}
