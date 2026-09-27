import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:genui/genui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/company_ticker_resolver.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/news_query_detector.dart';
import 'package:portfolio_assistant/features/assistant/modes/plan/plan_goal_saver.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/reliability/snapshot_grounding_validator.dart';
import 'package:portfolio_assistant/features/assistant/routing/intent_router.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_message_sync.dart';
import 'package:portfolio_assistant/features/assistant/unified/message_needs.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_access_policy.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_assistant_flag.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_context_builder.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_pipeline_deps.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_snapshot_validator.dart';
import 'package:portfolio_assistant/features/assistant/unified/unified_turn_history.dart';
import 'package:portfolio_assistant/features/assistant/utils/advice_notice_policy.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_snapshot_builder.dart';
import 'package:portfolio_assistant/features/genui_core/genui_surface_ids.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_flow_screen_helpers.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_request_tracker.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_send_guard.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_surface_readiness.dart';
import 'package:portfolio_assistant/features/investor_profile/providers/investor_profile_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

class AssistantProvider extends StateNotifier<AssistantState> {
  AssistantProvider({required this.ref, required AssistantArgs args})
    : _lastEngineMode = _collapsePlan(args.initialMode),
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

  // Pipeline unificado (flag `UnifiedAssistantFlag`): UN solo servicio y
  // UN solo historial para lo que antes eran portfolio/learn/explore.
  AssistantOpenAiService? _unifiedService;
  GenUiConversationSubscription? _unifiedSubscription;
  CompanyTickerResolver? _unifiedTickerResolver;

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

  // El aviso de completar/revisar el perfil de inversor sale una sola vez
  // por conversación — ver `AdviceNoticePolicy.profileNudge`.
  bool _profileNudgeShown = false;

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

  /// Servicio cuya conversación contiene la surface de [message]: el de su
  /// modo, o el unificado para las respuestas sin modo.
  AssistantOpenAiService? serviceForMessage(PortfolioQaMessage message) {
    final mode = message.engineMode;
    if (mode != null) return _services[mode];
    final surfaceId = message.surfaceId;
    if (surfaceId != null &&
        surfaceId.startsWith(GenUiSurfaceIds.assistantUnifiedPrefix)) {
      return _unifiedService;
    }
    return null;
  }

  void disposeResources() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    for (final service in _services.values) {
      service.dispose();
    }
    _subscriptions.clear();
    _services.clear();
    _unifiedSubscription?.cancel();
    _unifiedService?.dispose();
    _unifiedSubscription = null;
    _unifiedService = null;
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
    // Con el flag, todo lo que no es Invertir/Planificar va al pipeline
    // unificado: el modo que devolvió el router (portfolio/learn/explore)
    // deja de importar — ni catálogo ni contexto dependen de él. El gating
    // de plan pasa a ser por dato (ver `_sendUnified`).
    if (UnifiedAssistantFlag.enabled && _isUnifiedEngine(engineMode)) {
      _lastEngineMode = engineMode;
      await _sendUnified(trimmed);
      return;
    }
    // TEMP(debug precio sin datos): a qué motor se ruteó cada mensaje.
    // Solo explore arma datos de ticker. Borrar una vez diagnosticado.
    if (kDebugMode) {
      debugPrint(
        '[Assistant/route] engine=${engineMode.name} '
        '(last=${_lastEngineMode.name}) msg="$trimmed"',
      );
    }

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

  static bool _isUnifiedEngine(AssistantMode mode) =>
      mode != AssistantMode.invest && mode != AssistantMode.plan;

  void _ensureUnifiedService() {
    if (_unifiedService != null) return;
    final service = ref.read(unifiedPipelineDepsProvider).createService();
    _unifiedService = service;
    _unifiedSubscription =
        GenUiConversationSubscription()
          ..listen(service.conversation, _onConversationEvent);
  }

  /// Pipeline unificado: cada mensaje decide desde cero qué datos necesita
  /// ([MessageNeedsAnalyzer]), qué gating aplica ([UnifiedAccessPolicy], por
  /// dato y antes de pedir nada), y el modelo elige el widget sobre un
  /// catálogo único. Duplica a propósito el manejo de envío/errores de
  /// [sendMessage] para no tocar el pipeline por modos mientras conviven;
  /// la duplicación se va cuando se borre ese pipeline.
  Future<void> _sendUnified(String trimmed) async {
    if (!_sendGuard.tryAcquire()) return;
    state = state.copyWith(clearError: true, isWaiting: true);

    try {
      _ensureUnifiedService();
      final service = _unifiedService!;
      final deps = ref.read(unifiedPipelineDepsProvider);
      final subscription = ref.read(subscriptionProvider.notifier);
      await subscription.refresh();
      final tier = ref.read(subscriptionProvider).tier;
      final summary = ref.read(homeProvider).summary;

      final needs = await MessageNeedsAnalyzer.analyze(
        message: trimmed,
        summary: summary,
        followUpTicker: UnifiedTurnHistory.followUpTicker(state.messages),
        tickerResolver: _unifiedTickerResolver ??= deps.createTickerResolver(),
      );

      final paywall =
          UnifiedAccessPolicy.paywallFor(needs, tier) ??
          await subscription.checkQuotaAllowed(
            isNewsQuery: needs.isExplicitNewsRequest,
          );
      if (paywall != null) {
        state = state.copyWith(
          paywallReason: paywall,
          clearPaywallReason: false,
        );
        return;
      }

      final newsAllowed = UnifiedAccessPolicy.hasNews(tier);
      final snapshot = await UnifiedContextBuilder.build(
        needs: needs,
        userMessage: trimmed,
        quoteRepository: ref.read(quoteRepositoryProvider),
        marketDataAllowed: UnifiedAccessPolicy.hasMarketData(tier),
        newsAllowed: newsAllowed,
        summary: summary,
        history: ref.read(homeProvider).history,
        closedPositions: await _fetchClosedPositions(),
        newsEnricher: newsAllowed ? deps.createNewsEnricher() : null,
        earningsEnricher: newsAllowed ? deps.createEarningsEnricher() : null,
      );

      if (UnifiedSnapshotValidator.allRequestedTickersFailed(snapshot)) {
        state = state.copyWith(error: 'assistant_explore_fetch_failed'.tr());
        return;
      }

      // TEMP(debug precio sin datos): borrar junto con los demás logs TEMP.
      if (kDebugMode) {
        debugPrint(
          '[Unified/needs] tickers=${needs.tickers} held=${needs.heldTickers} '
          'conceptual=${needs.isConceptual} own=${needs.mentionsOwnPortfolio} '
          'followUp=${needs.usedFollowUpTicker} '
          'allPeriods=${needs.needsAllPositionPeriods}',
        );
      }

      final surfaceId = GenUiSurfaceIds.assistantUnifiedTurn(state.turnCounter);
      state = state.copyWith(
        messages: [
          ...state.messages,
          PortfolioQaMessage(role: PortfolioQaRole.user, content: trimmed),
          PortfolioQaMessage(
            role: PortfolioQaRole.assistant,
            surfaceId: surfaceId,
            isStreaming: true,
            subjectTickers: [
              for (final t in needs.tickers)
                if (t != needs.marketProxyTicker) t,
            ],
          ),
        ],
        lastMessage: trimmed,
        turnCounter: state.turnCounter + 1,
      );

      try {
        await GenUiRequestTracker.sendAndWait(
          conversation: service.conversation,
          targetSurfaceId: surfaceId,
          send:
              () => service.sendWithSnapshot(
                userQuestion: trimmed,
                portfolioSnapshotJson: jsonEncode(snapshot),
                surfaceId: surfaceId,
              ),
        );
        state = state.copyWith(
          messages: AssistantMessageSync.applySurfaceReady(
            state.messages,
            surfaceId,
            hasRootComponent: true,
          ),
        );
        final weight = SubscriptionPolicy.queryWeight(
          isNewsQuery: needs.isExplicitNewsRequest,
        );
        final consumed = await ref
            .read(aiUsageTrackerProvider)
            .recordUsage(weight);
        await subscription.refresh();
        if (!consumed) {
          state = state.copyWith(paywallReason: PaywallReason.quotaExceeded);
        }
      } on TimeoutException {
        state = state.copyWith(
          messages: AssistantMessageSync.applyFallback(
            state.messages,
            surfaceId,
            null,
          ),
        );
      } catch (e) {
        state = state.copyWith(
          error: isConnectionFailure(e) ? genUiErrorMessage(e) : state.error,
          messages:
              isConnectionFailure(e)
                  ? _removeStreamingPlaceholder(state.messages)
                  : AssistantMessageSync.applyFallback(
                    state.messages,
                    surfaceId,
                    null,
                  ),
        );
      }
    } finally {
      _sendGuard.release();
      state = state.copyWith(isWaiting: false);
    }
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

  Future<void> sendMessage(
    String text, {
    required AssistantMode engineMode,
  }) async {
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

      // Gatea y cobra solo pedidos EXPLÍCITOS de noticias — ver
      // `isExplicitNewsRequest`. El contexto sigue usando el detector
      // amplio para decidir si trae titulares (y marcarlos `locked`).
      final isNews =
          engineMode == AssistantMode.explore && isExplicitNewsRequest(trimmed);
      await ref.read(subscriptionProvider.notifier).refresh();
      final paywall = await ref
          .read(subscriptionProvider.notifier)
          .checkQueryAllowed(mode: engineMode, isNewsQuery: isNews);
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
        final errorKey =
            tickers == null || tickers.isEmpty
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

      final profileNudge = AdviceNoticePolicy.profileNudge(
        engineMode,
        snapshot,
        alreadyShown: _profileNudgeShown,
      );
      if (profileNudge != null) _profileNudgeShown = true;

      final surfaceId = GenUiSurfaceIds.assistantTurn(
        engineMode,
        state.turnCounter,
      );
      final messages = <PortfolioQaMessage>[
        ...state.messages,
        PortfolioQaMessage(role: PortfolioQaRole.user, content: trimmed),
        PortfolioQaMessage(
          role: PortfolioQaRole.assistant,
          surfaceId: surfaceId,
          isStreaming: true,
          engineMode: engineMode,
          showsAdviceDisclaimer: AdviceNoticePolicy.showsDisclaimer(
            engineMode,
            snapshot,
          ),
          profileNudge: profileNudge,
        ),
      ];

      state = state.copyWith(
        messages: messages,
        lastMessage: trimmed,
        turnCounter: state.turnCounter + 1,
      );

      try {
        await GenUiRequestTracker.sendAndWait(
          conversation: targetService.conversation,
          targetSurfaceId: surfaceId,
          send:
              () => targetService.sendWithSnapshot(
                userQuestion: trimmed,
                portfolioSnapshotJson: snapshotJson,
                surfaceId: surfaceId,
              ),
        );

        state = state.copyWith(
          // `sendAndWait` ya validó hasRootComponent para resolver — ver
          // GenUiRequestTracker.
          messages: AssistantMessageSync.applySurfaceReady(
            state.messages,
            surfaceId,
            hasRootComponent: true,
          ),
        );

        final weight = SubscriptionPolicy.queryWeight(isNewsQuery: isNews);
        final consumed = await ref
            .read(aiUsageTrackerProvider)
            .recordUsage(weight);
        await ref.read(subscriptionProvider.notifier).refresh();
        if (!consumed) {
          state = state.copyWith(paywallReason: PaywallReason.quotaExceeded);
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
    final closedResult =
        await ref.read(getClosedPositionsUseCaseProvider).call();
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
      final investorProfile =
          await ref.read(investorProfileProvider.notifier).refresh();
      return buildSnapshotJson(
        mode: AssistantMode.invest,
        userMessage: trimmed,
        summary: summary,
        history: history,
        closedPositions: await _fetchClosedPositions(),
        quoteRepository: ref.read(quoteRepositoryProvider),
        investorProfile: investorProfile,
      );
    }

    if (mode == AssistantMode.plan) {
      final prefs = ref.read(preferenceManagerProvider);
      final savedGoal = await prefs.getSavedGoal();
      final monthlyContribution = await prefs.getMonthlyContribution();
      final investorProfile =
          await ref.read(investorProfileProvider.notifier).refresh();
      return buildSnapshotJson(
        mode: AssistantMode.plan,
        userMessage: trimmed,
        summary: summary,
        history: history,
        closedPositions: await _fetchClosedPositions(),
        savedGoal: savedGoal,
        monthlyContribution: monthlyContribution,
        investorProfile: investorProfile,
      );
    }

    return buildSnapshotJson(mode: mode);
  }
}

final assistantProvider = StateNotifierProvider.autoDispose
    .family<AssistantProvider, AssistantState, AssistantArgs>((ref, args) {
      final provider = AssistantProvider(ref: ref, args: args);
      ref.onDispose(provider.disposeResources);
      return provider;
    });
