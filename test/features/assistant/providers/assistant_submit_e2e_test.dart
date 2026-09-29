import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/subscription_status.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/closed_position_repository.dart';
import 'package:portfolio_assistant/domain/repositories/investor_profile_repository.dart';
import 'package:portfolio_assistant/domain/repositories/subscription_repository.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_tracker.dart';
import 'package:portfolio_assistant/domain/use_cases/delete_positions_by_ticker_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_benchmark_comparison_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_history_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_portfolio_summary_use_case.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/providers/assistant_provider.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_deps.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/investor_profile/providers/investor_profile_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/revenue_cat_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../fakes/assistant_fakes.dart';

/// Punta a punta de `submitMessage`: cuota → placeholder → turno con tools
/// (servicio y loop reales) → gating al ejecutar cada tool → A2UI al
/// controller → mensajes, avisos y cuota. Lo único falso es OpenAI (a nivel
/// HTTP, con respuestas guionadas) y las fuentes externas.
class _FakeSubscriptionRepository implements SubscriptionRepository {
  _FakeSubscriptionRepository(this.tier, {this.used = 0});

  final SubscriptionTier tier;
  final int used;
  final consumed = <int>[];

  @override
  Future<SubscriptionStatus> fetchStatus() async => SubscriptionStatus(
    tier: tier,
    queriesUsed: used,
    queriesLimit: 20,
    month: '2026-09',
  );

  @override
  Future<bool> consumeQuota(int weight) async {
    consumed.add(weight);
    return true;
  }
}

class _Session implements SupabaseAuthService {
  _Session({this.signedIn = true});

  final bool signedIn;

  @override
  Session? get currentSession =>
      signedIn
          ? Session(
            accessToken: 'token',
            tokenType: 'bearer',
            user: const User(
              id: 'user',
              appMetadata: {},
              userMetadata: {},
              aud: 'authenticated',
              createdAt: '2026-01-01T00:00:00Z',
            ),
          )
          : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Unused {
  @override
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

class _UnusedProfileRepository extends _Unused
    implements InvestorProfileRepository {}

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
  _Harness(
    SubscriptionTier tier,
    List<Map<String, Object?> Function(Map<String, dynamic>)> script, {
    int used = 0,
  }) : subscriptionRepo = _FakeSubscriptionRepository(tier, used: used),
       api = ScriptedOpenAi(script) {
    final tracker = AiUsageTracker(repository: subscriptionRepo);
    container = ProviderContainer(
      overrides: [
        homeProvider.overrideWith((ref) => _LoadedHome(ref)),
        getClosedPositionsUseCaseProvider.overrideWithValue(
          _NoClosedPositions(),
        ),
        aiUsageTrackerProvider.overrideWithValue(tracker),
        revenueCatServiceProvider.overrideWithValue(_UnusedRevenueCat()),
        subscriptionProvider.overrideWith(
          (ref) => SubscriptionNotifier(
            tracker: tracker,
            authService: _Session(),
            revenueCat: _UnusedRevenueCat(),
          ),
        ),
        investorProfileProvider.overrideWith(
          (ref) => InvestorProfileNotifier(
            repository: _UnusedProfileRepository(),
            authService: _Session(signedIn: false),
          ),
        ),
        assistantDepsProvider.overrideWithValue(
          AssistantDeps(
            createService:
                () => AssistantOpenAiService(
                  apiKey: 'test',
                  model: 'gpt-4.1-mini',
                  httpClient: api.client,
                ),
            createData: () => fakeDataSources(quotes: quotes),
          ),
        ),
      ],
    );
    // autoDispose: mantener vivo el provider durante todo el test.
    container.listen(assistantProvider(args), (_, _) {});
  }

  static const args = AssistantArgs();
  final _FakeSubscriptionRepository subscriptionRepo;
  final ScriptedOpenAi api;
  final quotes = CountingQuoteRepository();
  late final ProviderContainer container;

  AssistantProvider get notifier =>
      container.read(assistantProvider(args).notifier);
  AssistantState get state => container.read(assistantProvider(args));

  PortfolioQaMessage get lastAnswer => state.messages.last;

  void dispose() => container.dispose();
}

Map<String, Object?> Function(Map<String, dynamic>) _answer([
  String text = 'ok',
]) {
  return (body) {
    final messages = (body['messages'] as List).cast<Map>();
    final lastUser = messages.lastWhere((m) => m['role'] == 'user');
    final content = (lastUser['content'] as List).first['text'] as String;
    final surfaceId = RegExp(r'SURFACE_ID[^:]*: (\S+)').firstMatch(content)!;
    return textReply(a2uiAnswer(surfaceId.group(1)!, text));
  };
}

Map<String, Object?> Function(Map<String, dynamic>) _call(
  String name,
  Map<String, Object?> args, {
  String id = 'call_1',
}) => (_) => toolCallsReply([(id, name, args)]);

String _textOf(Map message) {
  final content = message['content'];
  if (content is String) return content;
  if (content is! List) return '';
  return content.map((c) => (c as Map)['text'] ?? '').join();
}

void main() {
  _Harness harness(
    SubscriptionTier tier,
    List<Map<String, Object?> Function(Map<String, dynamic>)> script, {
    int used = 0,
  }) {
    final h = _Harness(tier, script, used: used);
    addTearDown(h.dispose);
    return h;
  }

  test('a portfolio question is answered in one request with the portfolio '
      'brief and every tool offered', () async {
    final h = harness(SubscriptionTier.free, [_answer('Tu cartera vale 600.')]);

    await h.notifier.submitMessage('¿Cómo está mi cartera?');

    expect(h.api.requests, hasLength(1));
    final request = h.api.requests.single;
    final messages = (request['messages'] as List).cast<Map>();
    // La cartera va como contexto fijo antes de la conversación, no pegada
    // a la pregunta (pegada, el modelo la tomaba como sujeto de los
    // seguimientos — ver ConversationLog.pinnedContext).
    expect(messages.map((m) => m['role']), ['system', 'system', 'user']);
    expect(_textOf(messages[1]), contains('PORTFOLIO_BRIEF'));
    expect(_textOf(messages[1]), contains('"ticker":"AAPL"'));
    expect(_textOf(messages[2]), endsWith('¿Cómo está mi cartera?'));
    expect(
      (request['tools'] as List).map((t) => (t as Map)['function']['name']),
      containsAll(['get_quote', 'get_news', 'get_invest_candidates']),
    );
    expect(h.lastAnswer.isStreaming, isFalse);
    expect(h.lastAnswer.isFallback, isFalse);
    expect(h.subscriptionRepo.consumed, [1]);
    expect(h.quotes.priceCalls, isEmpty);
  });

  test('free user asking for a ticker they do not hold: the model asks for '
      'it, the tool is locked, and the paywall replaces the turn', () async {
    final h = harness(SubscriptionTier.free, [
      _call('get_quote', {
        'tickers': ['AMZN'],
      }),
    ]);

    await h.notifier.submitMessage('¿A cuánto está AMZN?');

    expect(h.state.paywallReason, PaywallReason.marketDataLocked);
    expect(h.state.messages, hasLength(1)); // solo la bienvenida
    expect(h.subscriptionRepo.consumed, isEmpty);
    expect(h.quotes.priceCalls, isEmpty); // nunca se pidió el dato
    expect(h.api.requests, hasLength(1));
  });

  test(
    'free user, held ticker: the quote is fetched and the turn completes',
    () async {
      final h = harness(SubscriptionTier.free, [
        _call('get_quote', {
          'tickers': ['AAPL'],
        }),
        _answer(),
      ]);

      await h.notifier.submitMessage('¿A cuánto está AAPL?');

      expect(h.state.paywallReason, isNull);
      expect(h.quotes.priceCalls, ['AAPL']);
      expect(h.api.rolesOf(1), [
        'system',
        'system',
        'user',
        'assistant',
        'tool',
      ]);
      final toolResult =
          jsonDecode(_textOf((h.api.requests[1]['messages'] as List)[4] as Map))
              as Map;
      expect(toolResult['tickers']['AAPL']['held'], isTrue);
      expect(h.lastAnswer.isStreaming, isFalse);
    },
  );

  test(
    'G1: a follow-up without a ticker sees the previous turn tool result',
    () async {
      final h = harness(SubscriptionTier.free, [
        _call('get_quote', {
          'tickers': ['AAPL'],
        }),
        _answer(),
        _answer('Subió 1,2% hoy.'),
      ]);

      await h.notifier.submitMessage('¿A cuánto está AAPL?');
      await h.notifier.submitMessage('¿cuánto subió?');

      final roles = h.api.rolesOf(2);
      expect(roles, [
        'system',
        'system', // PORTFOLIO_BRIEF actual (uno solo, reemplazado)
        'user',
        'assistant',
        'tool',
        'assistant',
        'user',
      ]);
      final followUp = (h.api.requests[2]['messages'] as List).cast<Map>();
      expect(_textOf(followUp[4]), contains('"AAPL"'));
      expect(_textOf(followUp[2]), '¿A cuánto está AAPL?');
      expect(
        followUp.where((m) => _textOf(m).startsWith('PORTFOLIO_BRIEF')),
        hasLength(1),
      );
    },
  );

  test('a news search costs 3; a premium user asking for news gets the gold '
      'paywall', () async {
    final gold = harness(SubscriptionTier.gold, [
      _call('get_news', {
        'tickers': ['NVDA'],
      }),
      _answer(),
    ]);
    await gold.notifier.submitMessage('¿Qué noticias hay de NVDA?');
    expect(gold.subscriptionRepo.consumed, [3]);

    final premium = harness(SubscriptionTier.premium, [
      _call('get_news', {
        'tickers': ['NVDA'],
      }),
    ]);
    await premium.notifier.submitMessage('¿Qué noticias hay de NVDA?');
    expect(premium.state.paywallReason, PaywallReason.newsRequiresGold);
    expect(premium.subscriptionRepo.consumed, isEmpty);
  });

  test(
    'premium fundamentals are locked but not a paywall: the model words it',
    () async {
      final h = harness(SubscriptionTier.premium, [
        _call('get_fundamentals', {
          'tickers': ['AAPL'],
        }),
        _answer('Los fundamentals no están en tu plan.'),
      ]);

      await h.notifier.submitMessage('¿Cuál es el P/E de AAPL?');

      expect(h.state.paywallReason, isNull);
      final toolResult =
          jsonDecode(
                _textOf((h.api.requests[1]['messages'] as List).last as Map),
              )
              as Map;
      expect(toolResult['status'], 'locked');
      expect(h.subscriptionRepo.consumed, [1]);
    },
  );

  test('gold investment simulation shows the disclaimer and, once, the '
      'profile nudge', () async {
    final h = harness(SubscriptionTier.gold, [
      _call('get_invest_candidates', {
        'tickers': ['NEE', 'KO'],
        'budget_usd': 500,
      }),
      _answer(),
      _call('get_invest_candidates', {
        'tickers': ['NEE', 'KO'],
        'budget_usd': 500,
      }),
      _answer(),
    ]);

    await h.notifier.submitMessage('Tengo \$500 para invertir');
    expect(h.lastAnswer.showsAdviceDisclaimer, isTrue);
    expect(h.lastAnswer.profileNudge, InvestorProfileNudge.missing);

    await h.notifier.submitMessage('¿y otra idea?');
    expect(h.lastAnswer.showsAdviceDisclaimer, isTrue);
    expect(h.lastAnswer.profileNudge, isNull);
  });

  test('a non-gold user asking to invest gets the plan paywall', () async {
    final h = harness(SubscriptionTier.premium, [
      _call('get_invest_candidates', {
        'tickers': ['NEE', 'KO'],
        'budget_usd': 500,
      }),
    ]);

    await h.notifier.submitMessage('Tengo \$500 para invertir');

    expect(h.state.paywallReason, PaywallReason.modeLocked);
    expect(h.state.messages, hasLength(1));
  });

  test('no quota left: paywall before any request', () async {
    final h = harness(SubscriptionTier.free, [_answer()], used: 20);

    await h.notifier.submitMessage('Hola');

    expect(h.state.paywallReason, PaywallReason.quotaExceeded);
    expect(h.api.requests, isEmpty);
    expect(h.state.messages, hasLength(1));
  });

  test('a broken generation falls back to text instead of leaving the user '
      'without an answer', () async {
    final h = harness(SubscriptionTier.free, [
      (_) => textReply('no json here'),
      (_) => textReply('still no json'),
      (_) => textReply('nope'),
    ]);

    await h.notifier.submitMessage('Hola');

    // El sanitizer convierte el texto sin JSON en un fallback A2UI válido,
    // así que el turno termina con una surface (no con error).
    expect(h.lastAnswer.isStreaming, isFalse);
    expect(h.state.error, isNull);
  });
}
