import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:genui/genui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/company_ticker_resolver.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/jev_shadow/jev_shadow_repository.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/jev_shadow/jev_shadow_runner.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/jev_shadow/typesafe_client.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/news_query_detector.dart';
import 'package:portfolio_assistant/features/assistant/modes/plan/plan_goal_saver.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/reliability/snapshot_grounding_validator.dart';
import 'package:portfolio_assistant/features/assistant/routing/intent_router.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_message_sync.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_snapshot_builder.dart';
import 'package:portfolio_assistant/features/genui_core/genui_surface_ids.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_flow_screen_helpers.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_request_tracker.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_send_guard.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_surface_readiness.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

class AssistantProvider extends StateNotifier<AssistantState> {
  AssistantProvider({
    required this.ref,
    required AssistantArgs args,
  }) : _lastEngineMode = _collapsePlan(args.initialMode),
       super(
         AssistantState(
           messages: [
             PortfolioQaMessage(
               role: PortfolioQaRole.assistant,
               content: 'assistant_unified_welcome'.tr(),
             ),
           ],
         ),
       ) {
    _initialQuestion = args.initialQuestion;
  }

  final Ref ref;
  final _sendGuard = GenUiSendGuard();
  final _surfaceIds = <String>[];

  // Una conversación (servicio + suscripción a sus eventos) por motor, para
  // que cada dominio (portfolio/learn/explore/invest/plan) conserve su propio
  // contexto de cara a la IA aunque el chat que ve el usuario sea uno solo.
  // No se disponen durante la vida de la pantalla, solo en `disposeResources`.
  final Map<AssistantMode, AssistantOpenAiService> _services = {};
  final Map<AssistantMode, GenUiConversationSubscription> _subscriptions = {};

  // Último motor que atendió un turno. Da continuidad cuando un mensaje es
  // ambiguo (no matchea keywords de ningún dominio): el chat sigue con el
  // mismo motor en vez de saltar arbitrariamente a otro.
  AssistantMode _lastEngineMode;

  // Último ticker resuelto en un turno explore exitoso (mismo criterio de
  // continuidad que `_lastEngineMode`) — permite que un follow-up sin
  // ticker explícito ("¿y qué expectativas hay sobre estos resultados?")
  // siga refiriéndose a la misma compañía. Nunca avanza para el proxy de
  // mercado (SPY) ni cuando el turno no resolvió ningún ticker.
  String? _lastExploreTicker;

  // Resolver de nombre de compañía -> ticker (Finnhub /search). No
  // tier-gated: a diferencia de noticias/calendario, es la feature base de
  // explore funcionando, no un add-on premium. Lazy: construirlo toca
  // `dotenv.env` (vía `FinnhubHttpClient`), que en tests que no ejercitan
  // `sendMessage` (ver assistant_provider_test.dart) nunca se inicializa —
  // instanciar esto en el constructor de `AssistantProvider` rompería esos
  // tests aunque nunca lleguen a usarlo.
  CompanyTickerResolver? _exploreTickerResolverInstance;
  CompanyTickerResolver get _exploreTickerResolver =>
      _exploreTickerResolverInstance ??= CompanyTickerResolver();

  String? _initialQuestion;

  static const List<String> _starterChipKeys = [
    'portfolio_qa_chip_today',
    'assistant_learn_chip_diversify',
    'assistant_explore_chip_nvda',
    'assistant_invest_chip_budget',
  ];

  /// Sugerencias iniciales, mezclando un poco de cada dominio ya que no hay
  /// pestañas que las agrupen por tema.
  List<String> get chipKeys => _starterChipKeys;

  /// Planificar no es un motor navegable por separado a los ojos del
  /// routing: comparte continuidad con Invertir (ver
  /// `IntentRouter.resolveInvestPlanEngine`).
  static AssistantMode _collapsePlan(AssistantMode mode) =>
      mode == AssistantMode.plan ? AssistantMode.invest : mode;

  AssistantOpenAiService? serviceFor(AssistantMode engineMode) =>
      _services[engineMode];

  void disposeResources() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    for (final service in _services.values) {
      service.dispose();
    }
    _subscriptions.clear();
    _services.clear();
  }

  Future<void> bootstrap() async {
    if (state.bootstrapped) return;

    state = state.copyWith(bootstrapped: true);

    final summary = ref.read(homeProvider).summary;
    if (summary == null) {
      await ref.read(homeProvider.notifier).refresh();
    }

    await _ensureServiceForMode(_lastEngineMode);
    state = state.copyWith(isServiceReady: true);

    final question = _initialQuestion?.trim();
    if (question != null && question.isNotEmpty) {
      await submitMessage(question);
    }
  }

  Future<void> submitMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sendGuard.isInFlight) return;

    final engineMode = IntentRouter.detectEngine(
      message: trimmed,
      lastEngine: _lastEngineMode,
    );

    if (!ref.read(subscriptionProvider.notifier).canAccessMode(engineMode)) {
      state = state.copyWith(
        paywallReason: PaywallReason.modeLocked,
        clearPaywallReason: false,
      );
      return;
    }

    _lastEngineMode = engineMode;
    await sendMessage(trimmed, engineMode: engineMode);
  }

  void clearPaywall() {
    state = state.copyWith(clearPaywallReason: true);
  }

  void clearErrorAndRetry() {
    final last = state.lastMessage;
    state = state.copyWith(clearError: true);
    if (last.isNotEmpty) {
      unawaited(submitMessage(last));
    }
  }

  Future<void> _ensureServiceForMode(AssistantMode engineMode) async {
    if (_services.containsKey(engineMode)) return;
    final service = AssistantOpenAiService.forMode(mode: engineMode);
    _services[engineMode] = service;
    final subscription = GenUiConversationSubscription();
    subscription.listen(service.conversation, _onConversationEvent);
    _subscriptions[engineMode] = subscription;
  }

  void _onConversationEvent(ConversationEvent event) {
    var messages = <PortfolioQaMessage>[...state.messages];
    String? error = state.error;
    var isWaiting = state.isWaiting;

    if (event case ConversationComponentsUpdated(
      :final surfaceId,
      :final definition,
    )) {
      messages = AssistantMessageSync.applySurfaceReady(
        messages,
        surfaceId,
        hasRootComponent: GenUiSurfaceReadiness.hasRootComponent(definition),
      );
    }

    GenUiFlowScreenHelpers.handleConversationEvent(
      event: event,
      surfaceIds: _surfaceIds,
      setError: (value) => error = value,
      setWaiting: (value) => isWaiting = value,
      onStateChanged: () {},
    );

    state = state.copyWith(
      messages: messages,
      error: error,
      clearError: error == null,
      isWaiting: isWaiting,
    );
  }

  /// Marca la surface de [surfaceId] como ya revelada — ver
  /// `PortfolioQaMessage.hasRevealed`. Se llama una sola vez, desde
  /// `PortfolioQaAssistantSurface.onFullyRevealed`, cuando el reveal
  /// secuencial de esa surface termina por primera vez.
  void markRevealed(String surfaceId) {
    final messages = state.messages;
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.surfaceId == surfaceId && !message.hasRevealed) {
        final updated = [...messages];
        updated[i] = message.copyWith(hasRevealed: true);
        state = state.copyWith(messages: updated);
        return;
      }
    }
  }

  /// Igual que [markRevealed], para el typewriter de una burbuja de usuario
  /// (que no tiene `surfaceId`). Los mensajes son append-only acá (ningún
  /// código de este provider inserta, borra ni reordena `state.messages`),
  /// así que el índice sigue identificando al mismo mensaje de forma
  /// estable durante toda la vida de la conversación — el mismo criterio
  /// que ya usa la `Key` de la fila en `AssistantScreen`.
  void markUserMessageRevealed(int index) {
    final messages = state.messages;
    if (index < 0 || index >= messages.length) return;
    final message = messages[index];
    if (message.hasRevealed) return;
    final updated = [...messages];
    updated[index] = message.copyWith(hasRevealed: true);
    state = state.copyWith(messages: updated);
  }

  /// Marca la cascada de entrada del saludo + chips de sugerencia como ya
  /// mostrada — ver `AssistantState.introRevealed`.
  void markIntroRevealed() {
    if (state.introRevealed) return;
    state = state.copyWith(introRevealed: true);
  }

  Future<void> sendMessage(String text, {required AssistantMode engineMode}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    // El lock se toma de forma sincrónica, antes de cualquier `await`, para
    // que no exista una ventana en la que dos envíos concurrentes pasen
    // ambos el chequeo. `isWaiting` se prende en el mismo instante para que
    // la UI (que se deshabilita según `isWaiting`) refleje exactamente la
    // ventana en la que el guard está tomado.
    if (!_sendGuard.tryAcquire()) return;
    state = state.copyWith(clearError: true, isWaiting: true);

    try {
      await _ensureServiceForMode(engineMode);
      final targetService = _services[engineMode];
      if (targetService == null) return;

      final isNews =
          engineMode == AssistantMode.explore && isNewsQuery(trimmed);
      await ref.read(subscriptionProvider.notifier).refresh();
      final paywall =
          await ref.read(subscriptionProvider.notifier).checkQueryAllowed(
        mode: engineMode,
        isNewsQuery: isNews,
      );
      if (paywall != null) {
        state = state.copyWith(
          paywallReason: paywall,
          clearPaywallReason: false,
        );
        return;
      }

      final snapshotJson = await _buildSnapshotJson(engineMode, trimmed);
      final snapshot = jsonDecode(snapshotJson) as Map<String, dynamic>;

      if (engineMode == AssistantMode.explore) {
        final tickers = snapshot['explore_tickers'];
        final isMarketProxy = snapshot['market_proxy_ticker'] != null;
        if (!isMarketProxy && tickers is Map && tickers.isNotEmpty) {
          _lastExploreTicker = tickers.keys.first as String;
        }
      }

      final validation = SnapshotGroundingValidator.validate(
        mode: engineMode,
        snapshot: snapshot,
      );

      if (engineMode == AssistantMode.portfolio &&
          validation == SnapshotValidation.noPortfolioData) {
        state = state.copyWith(error: 'portfolio_qa_no_positions'.tr());
        return;
      }

      if (engineMode == AssistantMode.explore &&
          validation == SnapshotValidation.exploreFetchFailed) {
        final tickers = snapshot['explore_tickers'] as Map?;
        final errorKey = tickers == null || tickers.isEmpty
            ? 'assistant_explore_no_ticker'
            : 'assistant_explore_fetch_failed';
        state = state.copyWith(error: errorKey.tr());
        return;
      }

      if (engineMode == AssistantMode.invest &&
          validation == SnapshotValidation.exploreFetchFailed) {
        state = state.copyWith(error: 'assistant_invest_fetch_failed'.tr());
        return;
      }

      if (engineMode == AssistantMode.plan) {
        await PlanGoalSaver.persistIfRequested(
          prefs: ref.read(preferenceManagerProvider),
          snapshot: snapshot,
          userMessage: trimmed,
        );
      }

      final surfaceId =
          GenUiSurfaceIds.assistantTurn(engineMode, state.turnCounter);
      final messages = <PortfolioQaMessage>[
        ...state.messages,
        PortfolioQaMessage(role: PortfolioQaRole.user, content: trimmed),
        PortfolioQaMessage(
          role: PortfolioQaRole.assistant,
          surfaceId: surfaceId,
          isStreaming: true,
          engineMode: engineMode,
        ),
      ];

      state = state.copyWith(
        messages: messages,
        lastMessage: trimmed,
        turnCounter: state.turnCounter + 1,
      );

      try {
        final pipelineStopwatch = Stopwatch()..start();
        await GenUiRequestTracker.sendAndWait(
          conversation: targetService.conversation,
          targetSurfaceId: surfaceId,
          send: () => targetService.sendWithSnapshot(
            userQuestion: trimmed,
            portfolioSnapshotJson: snapshotJson,
            surfaceId: surfaceId,
          ),
        );
        pipelineStopwatch.stop();

        state = state.copyWith(
          // `sendAndWait` ya validó hasRootComponent para resolver — ver
          // GenUiRequestTracker.
          messages: AssistantMessageSync.applySurfaceReady(
            state.messages,
            surfaceId,
            hasRootComponent: true,
          ),
        );

        // Shadow-mode de Jev/TypeSafe (dev-only, ver JevShadowConfig): se
        // dispara DESPUÉS de que el turno real ya se resolvió y se mostró,
        // fire-and-forget, solo para juntar datos de comparación — nunca
        // puede demorar ni afectar la respuesta de arriba.
        if (engineMode == AssistantMode.explore) {
          JevShadowRunner.runForExploreTurn(
            userMessage: trimmed,
            snapshot: snapshot,
            componentChoices: targetService.lastComponentChoices ?? const [],
            currentPipelineLatency: pipelineStopwatch.elapsed,
            client: ref.read(typeSafeClientProvider),
            repository: ref.read(jevShadowRepositoryProvider),
            userId: ref.read(supabaseAuthServiceProvider).currentUser?.id,
          );
        }

        final weight = SubscriptionPolicy.queryWeight(isNewsQuery: isNews);
        final consumed =
            await ref.read(aiUsageTrackerProvider).recordUsage(weight);
        await ref.read(subscriptionProvider.notifier).refresh();
        if (!consumed) {
          state = state.copyWith(
            paywallReason: PaywallReason.quotaExceeded,
          );
        }
      } on TimeoutException {
        // Tras agotar el reintento interno de OpenAIGenUiService, un
        // timeout es una falla de generación (el modelo no llegó a
        // tiempo), no de conexión — cae a una respuesta de texto simple
        // en vez del banner de error, que queda reservado para fallas de
        // conexión reales (ver isConnectionFailure).
        state = state.copyWith(
          messages: AssistantMessageSync.applyFallback(
            state.messages,
            surfaceId,
            engineMode,
          ),
        );
      } catch (e) {
        if (isConnectionFailure(e)) {
          state = state.copyWith(
            error: genUiErrorMessage(e),
            messages: _removeStreamingPlaceholder(state.messages),
          );
        } else {
          // JSON inválido, schema mal formado, "interfaz sin componente
          // raíz" — todas fallas de generación: nunca dejan al usuario
          // sin respuesta, cae a texto en vez de mostrar el error card.
          state = state.copyWith(
            messages: AssistantMessageSync.applyFallback(
              state.messages,
              surfaceId,
              engineMode,
            ),
          );
        }
      }
    } finally {
      // Se libera siempre, sin importar por qué rama se salió del bloque
      // (paywall, validación fallida, éxito o excepción), así el guard y
      // `isWaiting` nunca quedan trabados en `true`.
      _sendGuard.release();
      state = state.copyWith(isWaiting: false);
    }
  }

  List<PortfolioQaMessage> _removeStreamingPlaceholder(
    List<PortfolioQaMessage> messages,
  ) {
    if (messages.isEmpty || !messages.last.isStreaming) return messages;
    return messages.sublist(0, messages.length - 1);
  }

  /// El motor que atiende un turno cambia con cada mensaje (ver
  /// `IntentRouter.detectEngine`), pero el usuario ve un solo chat con
  /// Porty — así que TODOS los motores necesitan poder referirse a la
  /// cartera real del usuario (holdings, valor, PnL), no solo `portfolio`.
  Future<List<ClosedPosition>> _fetchClosedPositions() async {
    final closedResult = await ref.read(getClosedPositionsUseCaseProvider).call();
    return closedResult.fold((_) => <ClosedPosition>[], (list) => list);
  }

  Future<String> _buildSnapshotJson(AssistantMode mode, String trimmed) async {
    final summary = ref.read(homeProvider).summary;
    final history = ref.read(homeProvider).history;

    if (mode == AssistantMode.portfolio) {
      return buildSnapshotJson(
        mode: AssistantMode.portfolio,
        summary: summary,
        history: history,
        closedPositions: await _fetchClosedPositions(),
        quoteRepository: ref.read(quoteRepositoryProvider),
      );
    }

    if (mode == AssistantMode.learn) {
      return buildSnapshotJson(
        mode: AssistantMode.learn,
        summary: summary,
        history: history,
        closedPositions: await _fetchClosedPositions(),
      );
    }

    if (mode == AssistantMode.explore) {
      return buildSnapshotJson(
        mode: AssistantMode.explore,
        userMessage: trimmed,
        summary: summary,
        history: history,
        closedPositions: await _fetchClosedPositions(),
        quoteRepository: ref.read(quoteRepositoryProvider),
        // Calendario de resultados y noticias son la misma categoría de
        // dato externo premium (fuente paga/factual, no solo precios) —
        // reusan el mismo gate de tier que ya existía para noticias en vez
        // de introducir una política de suscripción nueva.
        enableNewsEnrichment: SubscriptionPolicy.isNewsAllowed(
          ref.read(subscriptionProvider).tier,
        ),
        enableEarningsCalendar: SubscriptionPolicy.isNewsAllowed(
          ref.read(subscriptionProvider).tier,
        ),
        fallbackExploreTicker: _lastExploreTicker,
        exploreTickerResolver: _exploreTickerResolver,
      );
    }

    if (mode == AssistantMode.invest) {
      final riskProfile =
          await ref.read(preferenceManagerProvider).getRiskProfile();
      return buildSnapshotJson(
        mode: AssistantMode.invest,
        userMessage: trimmed,
        summary: summary,
        history: history,
        closedPositions: await _fetchClosedPositions(),
        quoteRepository: ref.read(quoteRepositoryProvider),
        riskProfile: riskProfile,
      );
    }

    if (mode == AssistantMode.plan) {
      final prefs = ref.read(preferenceManagerProvider);
      final savedGoal = await prefs.getSavedGoal();
      final monthlyContribution = await prefs.getMonthlyContribution();
      return buildSnapshotJson(
        mode: AssistantMode.plan,
        userMessage: trimmed,
        summary: summary,
        history: history,
        closedPositions: await _fetchClosedPositions(),
        savedGoal: savedGoal,
        monthlyContribution: monthlyContribution,
      );
    }

    return buildSnapshotJson(mode: mode);
  }
}

final assistantProvider = StateNotifierProvider.autoDispose
    .family<AssistantProvider, AssistantState, AssistantArgs>(
  (ref, args) {
    final provider = AssistantProvider(ref: ref, args: args);
    ref.onDispose(provider.disposeResources);
    return provider;
  },
);
