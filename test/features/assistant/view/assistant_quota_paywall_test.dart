import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/company_brand.dart';
import 'package:portfolio_assistant/domain/entities/subscription_status.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/closed_position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/company_brand_repository.dart';
import 'package:portfolio_assistant/domain/repositories/investor_profile_repository.dart';
import 'package:portfolio_assistant/domain/repositories/subscription_repository.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_tracker.dart';
import 'package:portfolio_assistant/domain/use_cases/delete_positions_by_ticker_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_benchmark_comparison_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_history_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_summary_use_case.dart';
import 'package:portfolio_assistant/features/assistant/data/market_taste/market_taste_repository.dart';
import 'package:portfolio_assistant/features/assistant/providers/assistant_provider.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_deps.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/services/company_brand_loader.dart';
import 'package:portfolio_assistant/features/assistant/services/quota_nudge_memory.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/assistant/view/assistant_screen.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_composer_field.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';
import 'package:portfolio_assistant/features/investor_profile/providers/investor_profile_provider.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/subscription/config/conversion_flags.dart';
import 'package:portfolio_assistant/features/subscription/config/paywall_source.dart';
import 'package:portfolio_assistant/features/subscription/providers/revenue_cat_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/paywall_offer.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../subscription/paywall_test_harness.dart';
import '../fakes/assistant_fakes.dart';

// Pantalla real del chat con el plan Free: el contador en 0 abre el paywall
// de cuota (`quota_zero_header`) y la línea de cuota baja abre el de
// `quotaLow` (`quota_soft`). Correr: flutter test
// test/features/assistant/view/assistant_quota_paywall_test.dart
void main() {
  setUpAll(() {
    final es =
        jsonDecode(File('assets/translations/es-ES.json').readAsStringSync())
            as Map<String, dynamic>;
    Localization.load(const Locale('es', 'ES'), translations: Translations(es));
  });

  Future<_World> pumpScreen(
    WidgetTester tester, {
    required int used,
    List<Map<String, Object?> Function(Map<String, dynamic>)> script = const [],
    MarketTasteRepository? taste,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final world = _World(
      await SharedPreferences.getInstance(),
      used,
      script,
      taste: taste,
    );
    addTearDown(world.container.dispose);
    // Teléfono de 390 x 844; el sheet del paywall necesita alto.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: world.container,
        child: MaterialApp(
          theme: world.container.read(themeDataLightProvider),
          home: const AssistantScreen(),
        ),
      ),
    );
    // La suscripción carga (plan y cuota del repo falso).
    await tester.pump();
    await tester.pump();
    return world;
  }

  testWidgets('the counter at 0 opens the quota paywall with source '
      'quota_zero_header', (tester) async {
    final world = await pumpScreen(tester, used: 20);

    await tester.tap(find.text('0 restantes'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(world.events.of(ProductEvent.paywallViewed), [
      {
        'reason': 'quotaExceeded',
        'source': PaywallSource.quotaZeroHeader,
        'tier': 'free',
        'visible_tiers': ['gold', 'premium'],
        'queries_used': 20,
        'queries_limit': 20,
      },
    ]);
  });

  testWidgets('with 5 left the counter is not a button: no paywall', (
    tester,
  ) async {
    final world = await pumpScreen(tester, used: 15);

    await tester.tap(find.text('5 restantes'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));

    expect(world.events.of(ProductEvent.paywallViewed), isEmpty);
  });

  testWidgets('the low quota line shows the plan numbers and "Ver planes" '
      'opens the quotaLow paywall with source quota_soft', (tester) async {
    late final _World world;
    world = await pumpScreen(
      tester,
      used: 14,
      script: [
        (body) {
          world.repo.used += 1; // el servidor cobra al responder
          return _answer(body, 'Tu cartera vale 600 dólares.');
        },
      ],
    );

    await tester.enterText(find.byType(TextField), '¿Cómo está mi cartera?');
    await tester.pump();
    await tester.tap(find.byType(AssistantSendButton));
    await tester.pump();

    final line = find.text(
      'Te quedan 5 consultas este mes. Con Premium '
      'tenés 500.',
    );
    for (var i = 0; i < 3000 && line.evaluate().isEmpty; i++) {
      await tester.runAsync(() async {});
      await tester.pump(const Duration(milliseconds: 16));
    }
    // La línea entra con fade al terminar el reveal; hasta entonces no recibe
    // toques.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(line, findsOneWidget);

    await tester.ensureVisible(find.text('Ver planes'));
    await tester.tap(find.text('Ver planes'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final viewed = world.events.of(ProductEvent.paywallViewed).single;
    expect(viewed['reason'], 'quotaLow');
    expect(viewed['source'], PaywallSource.quotaSoft);
    expect(viewed['queries_used'], 15);
  });

  testWidgets('after the free market lookups: the answer shows the Premium '
      'line, "Ver Premium" opens the marketDataLocked paywall with source '
      'chat_market_teaser and both events are logged', (tester) async {
    final world = await pumpScreen(
      tester,
      used: 3,
      taste: FakeMarketTasteRepository(used: 3),
      script: [
        (_) => toolCallsReply([
          (
            'call_1',
            'get_quote',
            {
              'tickers': ['AMZN'],
            },
          ),
        ]),
        (body) => _answer(body, 'Amazon es una empresa de comercio.'),
      ],
    );

    await tester.enterText(find.byType(TextField), '¿Qué opinás de AMZN?');
    await tester.pump();
    await tester.tap(find.byType(AssistantSendButton));
    await tester.pump();

    final cta = find.text('Ver Premium');
    for (var i = 0; i < 3000 && cta.evaluate().isEmpty; i++) {
      await tester.runAsync(() async {});
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(world.events.of(ProductEvent.paywallViewed), isEmpty);
    expect(world.events.of(ProductEvent.marketTeaserShown), hasLength(1));
    expect(
      find.textContaining('Tus 3 consultas gratis de este mes ya se usaron'),
      findsOneWidget,
    );

    await tester.ensureVisible(cta);
    await tester.tap(cta);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final viewed = world.events.of(ProductEvent.paywallViewed).single;
    expect(viewed['reason'], 'marketDataLocked');
    expect(viewed['source'], PaywallSource.chatMarketTeaser);
  });
}

Map<String, Object?> _answer(Map<String, dynamic> body, String text) {
  final messages = (body['messages'] as List).cast<Map>();
  final lastUser = messages.lastWhere((m) => m['role'] == 'user');
  final content = (lastUser['content'] as List).first['text'] as String;
  final surfaceId = RegExp(r'SURFACE_ID[^:]*: (\S+)').firstMatch(content)!;
  return textReply(a2uiAnswer(surfaceId.group(1)!, text));
}

class _Repo implements SubscriptionRepository {
  _Repo(this.used);
  int used;

  @override
  Future<SubscriptionStatus> fetchStatus() async => SubscriptionStatus(
    tier: SubscriptionTier.free,
    queriesUsed: used,
    queriesLimit: 20,
    month: '2026-11',
  );

  @override
  Future<bool> consumeQuota(int weight) async => true;
}

class _World {
  _World(
    SharedPreferences prefs,
    int used,
    List<Map<String, Object?> Function(Map<String, dynamic>)> script, {
    MarketTasteRepository? taste,
  }) : repo = _Repo(used),
      api = ScriptedOpenAi(script) {
    final tracker = AiUsageTracker(repository: repo);
    final revenueCat = FakeRevenueCat(offer: PaywallOffer.empty);
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        supabaseAuthServiceProvider.overrideWithValue(_Session()),
        quotaNudgeEnabledProvider.overrideWith((_) async => true),
        quotaNudgeClockProvider.overrideWithValue(() => DateTime.utc(2026, 11)),
        paywallAnnualEnabledProvider.overrideWith((_) async => false),
        productEventsProvider.overrideWithValue(events),
        if (taste != null) marketTasteRepositoryProvider.overrideWithValue(taste),
        homeProvider.overrideWith((ref) => _LoadedHome(ref)),
        getClosedPositionsUseCaseProvider.overrideWithValue(
          _NoClosedPositions(),
        ),
        aiUsageTrackerProvider.overrideWithValue(tracker),
        revenueCatServiceProvider.overrideWithValue(revenueCat),
        subscriptionProvider.overrideWith(
          (ref) => SubscriptionNotifier(
            tracker: tracker,
            authService: _Session(),
            revenueCat: revenueCat,
          ),
        ),
        investorProfileProvider.overrideWith(
          (ref) => InvestorProfileNotifier(
            repository: _UnusedProfileRepo(),
            authService: _Session(signedIn: false),
          ),
        ),
        companyBrandLoaderProvider.overrideWithValue(
          CompanyBrandLoader(_NoBrands()),
        ),
        assistantDepsProvider.overrideWithValue(
          AssistantDeps(
            createService:
                () => AssistantOpenAiService(
                  proxy: AiProxyConfig.fixed(
                    Uri.parse('https://proxy.test'),
                    'jwt-test',
                  ),
                  model: 'gpt-4.1-mini',
                  httpClient: api.client,
                ),
            createData: () => fakeDataSources(),
          ),
        ),
      ],
    );
    // autoDispose: el provider vive mientras dure el test.
    container.listen(assistantProvider(const AssistantArgs()), (_, _) {});
  }

  final _Repo repo;
  final ScriptedOpenAi api;
  final events = FakeProductEvents();
  late final ProviderContainer container;
}

class _Session implements SupabaseAuthService {
  _Session({this.signedIn = true});
  final bool signedIn;

  static const _user = User(
    id: 'user',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  );

  @override
  User? get currentUser => signedIn ? _user : null;

  @override
  Session? get currentSession =>
      signedIn
          ? Session(accessToken: 'token', tokenType: 'bearer', user: _user)
          : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Unused {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected call: ${invocation.memberName}');
}

class _UnusedProfileRepo extends _Unused implements InvestorProfileRepository {}

class _UnusedSummary extends _Unused implements GetPortfolioSummaryUseCase {}

class _UnusedHistory extends _Unused implements GetPortfolioHistoryUseCase {}

class _UnusedBenchmark extends _Unused
    implements GetBenchmarkComparisonUseCase {}

class _UnusedDelete extends _Unused implements DeletePositionsByTickerUseCase {}

class _UnusedClosedRepo extends _Unused implements ClosedPositionRepository {}

class _NoBrands implements CompanyBrandRepository {
  @override
  Future<CompanyBrand?> getBrand(String ticker) async => null;
}

class _NoClosedPositions extends GetClosedPositionsUseCase {
  _NoClosedPositions() : super(repository: _UnusedClosedRepo());

  @override
  Future<Either<HttpError, List<ClosedPosition>>> call({void params}) async =>
      const Right([]);
}

class _LoadedHome extends HomeProvider {
  _LoadedHome(Ref ref)
    : super(
        ref: ref,
        getPortfolioSummaryUseCase: _UnusedSummary(),
        getPortfolioHistoryUseCase: _UnusedHistory(),
        getBenchmarkComparisonUseCase: _UnusedBenchmark(),
        deletePositionsByTickerUseCase: _UnusedDelete(),
        getClosedPositionsUseCase: _NoClosedPositions(),
      ) {
    state = HomeState(summary: heldSummary);
  }
}
