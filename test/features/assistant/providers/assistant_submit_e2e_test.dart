import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/subscription/ai_usage_limits.dart';
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
import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/providers/assistant_provider.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_deps.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/turn_activity.dart';
import 'package:portfolio_assistant/features/investor_profile/providers/investor_profile_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/revenue_cat_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/revenue_cat_service.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../fakes/assistant_fakes.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';

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
                  proxy: AiProxyConfig.fixed(Uri.parse('https://proxy.test'), 'jwt-test'),
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
    // La consulta la descuenta el proxy al responder, no la app.
    expect(h.subscriptionRepo.consumed, isEmpty);
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

  test(
    'a news search is answered for gold; a premium user asking for news '
    'gets an answer (with the Gold block), not an interrupting paywall; the '
    'app never charges (the proxy does)',
    () async {
      final gold = harness(SubscriptionTier.gold, [
        _call('get_news', {
          'tickers': ['NVDA'],
        }),
        _answer(),
      ]);
      await gold.notifier.submitMessage('¿Qué noticias hay de NVDA?');
      // Cobra el proxy (una consulta por turno), no la app.
      expect(gold.subscriptionRepo.consumed, isEmpty);

      final premium = harness(SubscriptionTier.premium, [
        _call('get_news', {
          'tickers': ['NVDA'],
        }),
        _answer('Las noticias están incluidas en Gold.'),
      ]);
      await premium.notifier.submitMessage('¿Qué noticias hay de NVDA?');
      expect(premium.state.paywallReason, isNull);
      expect(premium.subscriptionRepo.consumed, isEmpty);
    },
  );

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
      // Solo se pudo decir qué incluye Gold: no se cobra la consulta.
      expect(h.subscriptionRepo.consumed, isEmpty);
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

  // Desde la matriz de planes (2026-09-30) las simulaciones son de Premium:
  // el paywall lo ve Free.
  test('a free user asking to invest gets the plan paywall', () async {
    final h = harness(SubscriptionTier.free, [
      _call('get_invest_candidates', {
        'tickers': ['NEE', 'KO'],
        'budget_usd': 500,
      }),
    ]);

    await h.notifier.submitMessage('Tengo \$500 para invertir');

    expect(h.state.paywallReason, PaywallReason.modeLocked);
    expect(h.state.messages, hasLength(1));
  });

  test('no monthly quota: the server rejects the turn and the paywall '
      'replaces it', () async {
    final h = harness(SubscriptionTier.free, [
      (_) => proxyRejection(402, 'quota_exceeded'),
    ], used: 20);

    await h.notifier.submitMessage('Hola');

    expect(h.state.paywallReason, PaywallReason.quotaExceeded);
    expect(h.api.requests, hasLength(1));
    expect(h.state.messages, hasLength(1));
    expect(h.state.error, isNull);
    expect(h.state.isWaiting, isFalse);
  });

  test('daily cap: a quiet notice takes the answer slot — no paywall, no '
      'error banner — and the model never sees the turn', () async {
    final h = harness(SubscriptionTier.gold, [
      (_) => proxyRejection(429, 'daily_limit'),
      _answer('mañana'),
    ]);

    await h.notifier.submitMessage('¿Cómo está mi cartera?');

    expect(h.state.paywallReason, isNull);
    expect(h.state.error, isNull);
    expect(h.api.requests, hasLength(1), reason: 'sin reintentos');
    expect(h.state.messages, hasLength(3));
    expect(h.lastAnswer.notice, AssistantNotice.dailyLimit);
    expect(h.lastAnswer.isStreaming, isFalse);
    expect(h.lastAnswer.isGenUiSurface, isFalse);

    // El turno rechazado no queda en la memoria del modelo.
    await h.notifier.submitMessage('Hola de nuevo');
    final users = [
      for (final m in (h.api.requests.last['messages'] as List).cast<Map>())
        if (m['role'] == 'user') _textOf(m),
    ];
    expect(users, hasLength(1));
    expect(users.single, endsWith('Hola de nuevo'));
  });

  test('other server rejections show the error banner with a user-facing '
      'message', () async {
    final h = harness(SubscriptionTier.premium, [
      (_) => proxyRejection(429, 'rate_limited'),
    ]);

    await h.notifier.submitMessage('Hola');

    expect(h.state.paywallReason, isNull);
    expect(h.state.error, contains('muchas consultas seguidas'));
    expect(h.state.error, isNot(contains('OpenAI')));
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

  group('turn activity (Porty header status)', () {
    List<String> record(_Harness h) {
      final seen = <String>[];
      void listener() {
        final a = h.notifier.activity.value;
        seen.add(
          a.phase == TurnPhase.runningTools
              ? 'tools:${a.calls.map((c) => '${c.name}${c.args['tickers']}').join(',')}'
              : a.phase.name,
        );
      }

      h.notifier.activity.addListener(listener);
      addTearDown(() => h.notifier.activity.removeListener(listener));
      return seen;
    }

    test('follows the real loop: thinking, the requested tools with their '
        'arguments, composing, and idle when the turn ends', () async {
      final h = harness(SubscriptionTier.free, [
        _call('get_quote', {
          'tickers': ['AAPL'],
        }),
        _answer('AAPL está a 200.'),
      ]);
      final seen = record(h);

      await h.notifier.submitMessage('¿A cuánto está AAPL?');

      expect(seen, ['thinking', 'tools:get_quote[AAPL]', 'composing', 'idle']);
      expect(h.notifier.activity.value.isIdle, isTrue);
    });

    test('goes back to idle when the turn fails', () async {
      // Sin guion: el primer request responde 500.
      final h = harness(SubscriptionTier.free, []);
      final seen = record(h);

      await h.notifier.submitMessage('Hola');

      expect(seen.first, 'thinking');
      expect(seen.last, 'idle');
      expect(h.notifier.activity.value.isIdle, isTrue);
    });

    test('goes back to idle when the quota paywall stops the turn', () async {
      final h = harness(SubscriptionTier.free, [_answer()], used: 20);
      final seen = record(h);

      await h.notifier.submitMessage('Hola');

      expect(seen, ['thinking', 'idle']);
    });
  });

  group('portfolio actions', () {
    /// La respuesta con una card por cada propuesta ok que devolvió la tool.
    Map<String, Object?> answerWithProposals(Map<String, dynamic> body) {
      final messages = (body['messages'] as List).cast<Map>();
      final ids = [
        for (final m in messages.where((m) => m['role'] == 'tool'))
          (jsonDecode(_textOf(m)) as Map)['proposal_id'],
      ].whereType<String>().toList();
      final lastUser = messages.lastWhere((m) => m['role'] == 'user');
      final surfaceId =
          RegExp(
            r'SURFACE_ID[^:]*: (\S+)',
          ).firstMatch(_textOf(lastUser))!.group(1)!;
      final update = jsonEncode({
        'version': 'v0.9',
        'updateComponents': {
          'surfaceId': surfaceId,
          'components': [
            {
              'id': 'root',
              'component': 'Column',
              'children': ['a', for (var i = 0; i < ids.length; i++) 'p$i'],
            },
            {
              'id': 'a',
              'component': 'QaAnswerText',
              'text': 'Revisá los datos y confirmá.',
            },
            for (var i = 0; i < ids.length; i++)
              {'id': 'p$i', 'component': 'QaActionProposal', 'proposalId': ids[i]},
          ],
        },
      });
      return textReply(
        '{"version":"v0.9","createSurface":{"surfaceId":"$surfaceId",'
        '"catalogId":"https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}\n'
        '$update',
      );
    }

    test('premium: the proposal reaches the card evidence without saving, '
        'and the next turn knows it was cancelled', () async {
      final h = harness(SubscriptionTier.premium, [
        _call('propose_buy', {
          'ticker': 'AAPL',
          'shares': 10,
          'date': '2026-09-25',
        }),
        answerWithProposals,
        _answer('Listo.'),
      ]);

      await h.notifier.submitMessage('Compré 10 de Apple el 25 de septiembre');

      // Sin ronda de corrección: la card tiene su propuesta detrás.
      expect(h.api.requests, hasLength(2));
      expect(h.lastAnswer.isFallback, isFalse);
      final surfaceId = h.lastAnswer.surfaceId!;
      final calls =
          h.notifier.service!.evidenceListenable(surfaceId).value.calls;
      final proposal = ActionProposal.fromToolResult(
        calls.singleWhere((c) => c.name == 'propose_buy').result,
      )!;
      expect(proposal.ticker, 'AAPL');
      expect(proposal.shares, 10);
      // Nada se guardó: la propuesta sigue pendiente.
      expect(h.state.actionProgress(proposal.id).status,
          ActionProposalStatus.pending);

      h.notifier.cancelAction(
        ActionDraft(
          proposalId: proposal.id,
          kind: ActionKind.buy,
          ticker: 'AAPL',
          shares: 10,
          price: proposal.price,
          date: proposal.date,
        ),
      );
      await h.notifier.submitMessage('Gracias');

      final brief = _textOf(
        (h.api.requests.last['messages'] as List).cast<Map>()[1],
      );
      expect(brief, contains('"actions_this_conversation"'));
      expect(brief, contains('"status":"cancelled"'));
      expect(brief, contains(proposal.id));
    });

    test('free: proposing is locked and the Premium paywall replaces the '
        'turn', () async {
      final h = harness(SubscriptionTier.free, [
        _call('propose_buy', {
          'ticker': 'AAPL',
          'shares': 10,
          'date': '2026-09-25',
        }),
      ]);

      await h.notifier.submitMessage('Compré 10 de Apple el 25 de septiembre');

      expect(h.state.paywallReason, PaywallReason.modeLocked);
      expect(h.state.messages, hasLength(1));
      expect(h.quotes.dailyCalls, isEmpty);
    });
  });
}
