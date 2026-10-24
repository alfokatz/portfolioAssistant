import 'dart:async';

import 'package:dartz/dartz.dart' show Either;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:portfolio_assistant/presentation/base/theme/theme_mode_provider.dart';
import 'package:portfolio_assistant/features/weekly_report/providers/weekly_report_controller.dart';
import 'package:portfolio_assistant/features/binance/domain/binance_connection.dart';
import 'package:portfolio_assistant/features/etoro/view/etoro_messages.dart';
import 'package:portfolio_assistant/features/etoro/providers/etoro_connection_provider.dart';
import 'package:portfolio_assistant/features/binance/view/binance_screen.dart'
    show binanceErrorMessage;
import 'package:portfolio_assistant/features/binance/providers/binance_provider.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_currency.dart';
import 'package:portfolio_assistant/features/display_currency/providers/display_currency_provider.dart';
import 'package:portfolio_assistant/features/notifications/domain/notification_preferences.dart';
import 'package:portfolio_assistant/features/notifications/providers/notification_preferences_provider.dart';
import 'package:portfolio_assistant/features/allocation/domain/allocation_plan.dart';
import 'package:portfolio_assistant/features/allocation/providers/allocation_provider.dart';
import 'package:portfolio_assistant/features/watchlist/data/watchlist_repository.dart';
import 'package:portfolio_assistant/features/watchlist/providers/watchlist_provider.dart';
import 'package:genui/genui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/investor_profile.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/use_cases/add_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/close_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/delete_position_use_case.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/tools/market_tools.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/assistant/models/manage_action.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/models/porty_screen_context.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_deps.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/assistant/tools/action_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_toolset.dart';
import 'package:portfolio_assistant/features/assistant/tools/portfolio_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/weekly_free_analysis_grant.dart';
import 'package:portfolio_assistant/features/assistant/utils/answer_stream_preview.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_message_sync.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_flow_screen_helpers.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_request_tracker.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_send_guard.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_surface_readiness.dart';
import 'package:portfolio_assistant/features/investor_profile/providers/investor_profile_provider.dart';
import 'package:portfolio_assistant/features/notifications/domain/price_alert.dart';
import 'package:portfolio_assistant/features/notifications/providers/price_alerts_provider.dart';
import 'package:portfolio_assistant/features/goals/data/goals_repository.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/user_memory.dart';
import 'package:portfolio_assistant/features/porty_memory/providers/user_memory_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/weekly_free_analysis_provider.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

/// Un solo chat con Porty. Cada mensaje es un turno de tool calling: el
/// modelo decide qué datos pedir (ver `AssistantToolset`), el plan del
/// usuario se aplica al ejecutar cada tool, y la respuesta final es A2UI
/// que genui renderiza. No hay router ni modos.
class AssistantProvider extends StateNotifier<AssistantState> {
  AssistantProvider({required this.ref, required AssistantArgs args})
    : super(
        AssistantState(
          messages: [
            PortfolioQaMessage(
              role: PortfolioQaRole.assistant,
              content: 'assistant_unified_welcome'.tr(),
            ),
          ],
        ),
      ) {
    if (args.initialQuestion case final q?) {
      _initialQuestion = (text: q, screen: args.initialScreen);
    }
  }

  final Ref ref;
  final _sendGuard = GenUiSendGuard();
  final _surfaceIds = <String>[];

  AssistantOpenAiService? _service;
  GenUiConversationSubscription? _subscription;
  AssistantDataSources? _data;

  _OutsideQuestion? _initialQuestion;

  /// Pregunta llegada de afuera mientras corría un turno: sale apenas
  /// termina (ver [askFromOutside]).
  _OutsideQuestion? _queuedQuestion;

  /// La pantalla desde donde se abrió el chat por última vez (ver
  /// [PortyScreenContext]) y cuántos turnos pasaron desde entonces.
  PortyScreenContext? _screen;
  int _screenTurns = 0;

  /// La pregunta de afuera que está por salir cambia [_screen] (también a
  /// `null`: una pregunta de la Home no es sobre la pantalla anterior).
  bool _screenPending = false;
  PortyScreenContext? _pendingScreen;

  // El aviso de completar/revisar el perfil de inversor sale una sola vez
  // por conversación — ver `AssistantTurnPolicy.noticesFor`.
  bool _profileNudgeShown = false;

  /// Sugerencias iniciales según el plan: cada una se responde con lo que el
  /// plan incluye (ninguna lleva a un paywall gastando una consulta) y
  /// parten de la cartera del usuario antes que de un ticker cualquiera.
  /// Cubren lo que promete el saludo: cartera, conceptos, mercado y metas.
  @visibleForTesting
  static List<String> starterChipKeysFor(SubscriptionTier tier) =>
      switch (tier) {
        SubscriptionTier.free => const [
          'portfolio_qa_chip_today',
          'assistant_chip_diversified',
          'assistant_chip_best_position',
          'portfolio_qa_chip_risk',
        ],
        SubscriptionTier.premium => const [
          'portfolio_qa_chip_today',
          'assistant_chip_diversified',
          'assistant_explore_chip_compare',
          'assistant_chip_goal',
        ],
        SubscriptionTier.gold => const [
          'portfolio_qa_chip_today',
          'assistant_chip_why_moved',
          'assistant_chip_diversified',
          'assistant_chip_goal',
        ],
      };

  /// Sugerencias iniciales del plan actual (ver [starterChipKeysFor]).
  List<String> get chipKeys =>
      starterChipKeysFor(ref.read(subscriptionProvider).tier);

  /// La conversación de Porty (sus surfaces). `null` hasta `bootstrap`.
  AssistantOpenAiService? get service => _service;

  // Fuera de [AssistantState] a propósito: cambia varias veces por turno y
  // solo le importa al header, no tiene por qué reconstruir el chat.
  final _activity = ValueNotifier<TurnActivity>(TurnActivity.idle);

  /// En qué anda el turno en curso (ver `PortyHeader`); `idle` entre turnos.
  ValueListenable<TurnActivity> get activity => _activity;

  void _setActivity(TurnActivity value) {
    if (mounted) _activity.value = value;
  }

  // Igual que [_activity]: cambia con cada pedazo de la respuesta y solo le
  // importa a la fila del turno en curso.
  final _preview = ValueNotifier<AnswerPreview?>(null);

  /// Con streaming: el texto de Porty del turno en curso mientras se
  /// escribe (solo el texto; las cards llegan con la respuesta completa).
  ValueListenable<AnswerPreview?> get preview => _preview;

  /// El texto que ya se vio en la vista previa de cada respuesta: la
  /// respuesta final no lo vuelve a tipear (ver `QaStreamedTextScope`).
  final _streamedTexts = <String, String>{};

  String? streamedTextFor(String surfaceId) => _streamedTexts[surfaceId];

  /// Cada cuánto se recalcula la vista previa (llegan ~100 pedazos por
  /// segundo; la pantalla no necesita más que esto).
  static const _previewInterval = Duration(milliseconds: 60);

  /// `onContent` del turno de [surfaceId]: el texto de la respuesta a medias.
  ContentDeltaCallback _previewSink(String surfaceId) {
    final clock = Stopwatch()..start();
    var last = Duration.zero - _previewInterval;
    _lastRaw = null;
    return (raw) {
      _lastRaw = raw;
      if (!mounted || clock.elapsed - last < _previewInterval) return;
      final text = AnswerStreamPreview.textOf(raw);
      if (text.isEmpty) return;
      last = clock.elapsed;
      _preview.value = AnswerPreview(surfaceId, text);
    };
  }

  /// Fin del turno de [surfaceId]: lo que se vio queda anotado y la vista
  /// previa se apaga.
  void _closePreview(String surfaceId) {
    final shown = _preview.value;
    if (shown != null && shown.surfaceId == surfaceId) {
      // El texto entero de lo último que llegó (la vista previa se
      // actualiza cada [_previewInterval] y pudo quedar un pedazo atrás).
      final raw = _lastRaw;
      final full = raw == null ? '' : AnswerStreamPreview.textOf(raw);
      _streamedTexts[surfaceId] = full.isEmpty ? shown.text : full;
    }
    _lastRaw = null;
    if (mounted) _preview.value = null;
  }

  /// La respuesta a medias más reciente del turno en curso.
  String? _lastRaw;

  @override
  void dispose() {
    _activity.dispose();
    _preview.dispose();
    super.dispose();
  }

  void disposeResources() {
    _subscription?.cancel();
    _service?.dispose();
    _subscription = null;
    _service = null;
  }

  Future<void> bootstrap() async {
    if (state.bootstrapped) return;

    state = state.copyWith(bootstrapped: true);

    // Mientras prepara la conversación (puede tener que traer la cartera),
    // Porty piensa en el header: no hay un loader aparte en el chat.
    final summary = ref.read(homeProvider).summary;
    if (summary == null) {
      _setActivity(TurnActivity.thinking);
      try {
        await ref.read(homeProvider.notifier).refresh();
      } finally {
        _setActivity(TurnActivity.idle);
      }
    }

    _leanPrompt = await _leanPromptForConversation();
    _ensureService();
    state = state.copyWith(isServiceReady: true);
    // Arranca la función del proxy mientras el usuario lee o escribe.
    if (ref.read(assistantDepsProvider).warmUpOnOpen) {
      unawaited(_service!.warmUp());
    }
    // La app pudo quedar abierta de domingo a lunes: semana nueva, cortesía
    // nueva. Sin Supabase (tests), no hace nada.
    try {
      unawaited(
        ref
            .read(weeklyFreeAnalysisProvider.notifier)
            .refreshIfNewWeek(
              eligible: PlanMatrix.hasWeeklyFreeAnalysis(
                ref.read(subscriptionProvider).tier,
              ),
            ),
      );
    } catch (_) {}

    final question = _initialQuestion;
    _initialQuestion = null;
    if (question != null && question.text.trim().isNotEmpty) {
      await _submitFromOutside(question);
    }
  }

  /// Pregunta tocada fuera del chat (chips de Home, de una posición, del
  /// informe) con la pantalla de Porty ya montada. Si la conversación
  /// todavía se está preparando, la toma `bootstrap`; si hay un turno en
  /// curso, sale cuando termina (la última tocada gana).
  ///
  /// [screen] es lo que el usuario estaba mirando (ver
  /// [PortyScreenContext]); `null` si la pregunta no es de una pantalla.
  void askFromOutside(String question, {PortyScreenContext? screen}) {
    final trimmed = question.trim();
    if (trimmed.isEmpty) return;
    final outside = (text: trimmed, screen: screen);
    if (!state.isServiceReady) {
      _initialQuestion = outside;
    } else if (state.isWaiting) {
      _queuedQuestion = outside;
    } else {
      unawaited(_submitFromOutside(outside));
    }
  }

  Future<void> _submitFromOutside(_OutsideQuestion question) {
    _screenPending = true;
    _pendingScreen = question.screen;
    return submitMessage(question.text);
  }

  /// El `screen_context` de este turno: la pantalla de la pregunta de
  /// afuera que sale ahora o, en los turnos siguientes, la misma con
  /// `turns_ago` sumando, hasta [PortyScreenContext.maxTurns].
  Map<String, Object?>? _screenForTurn() {
    if (_screenPending) {
      _screen = _pendingScreen;
      _screenTurns = 0;
      _screenPending = false;
      _pendingScreen = null;
    } else if (_screen != null) {
      _screenTurns++;
    }
    final screen = _screen;
    if (screen == null) return null;
    if (_screenTurns >= PortyScreenContext.maxTurns) {
      _screen = null;
      return null;
    }
    return screen.toBrief(turnsAgo: _screenTurns);
  }

  /// Si esta conversación usa el prompt lean (`PromptVariant.lean`). Se
  /// decide una vez, al abrir el chat: cambiar de prompt a mitad de una
  /// conversación rompería la caché y dejaría `area_spec` sin su regla.
  bool _leanPrompt = false;

  Future<bool> _leanPromptForConversation() async {
    final enabled = ref.read(assistantDepsProvider).leanPromptEnabled;
    if (enabled == null) return false;
    try {
      return await enabled();
    } catch (_) {
      return false;
    }
  }

  void _ensureService() {
    if (_service != null) return;
    final deps = ref.read(assistantDepsProvider);
    final service =
        (_leanPrompt ? deps.createLeanService : null)?.call() ??
        deps.createService();
    _service = service;
    _subscription =
        GenUiConversationSubscription()
          ..listen(service.conversation, _onConversationEvent);
  }

  /// Sin Supabase (tests, sin sesión), la cortesía simplemente no se ofrece.
  bool _weeklyFreeAvailable() =>
      ref.read(weeklyFreeAnalysisAvailableProvider) == true;

  /// Después de comprar Gold desde una card: trae las fuentes de Gold del
  /// ticker SIN pasar por el modelo (no cuesta una consulta) y las suma a
  /// la evidencia de esa surface, así las secciones bloqueadas se completan
  /// en el lugar. Mientras cargan, la card muestra skeletons.
  Future<void> unlockGoldData(String surfaceId, String ticker) async {
    final service = _service;
    if (service == null) return;
    final tier = ref.read(subscriptionProvider).tier;
    if (!PlanMatrix.allows(tier, PlanFeature.companyAnalysis)) return;
    service.setEvidenceLoading(surfaceId, loading: true);
    try {
      final data = _data ??= ref.read(assistantDepsProvider).createData();
      final ctx = AssistantToolContext(
        tier: tier,
        data: data,
        newsProvider: await data.newsProvider(),
        summary: ref.read(homeProvider).summary,
      );
      final args = <String, Object?>{
        'tickers': [ticker.toUpperCase()],
      };
      final records = await Future.wait([
        for (final tool in <DataTool>[
          GetFundamentalsTool(ctx),
          GetEarningsTool(ctx),
          GetNewsTool(ctx),
        ])
          tool
              .run(args)
              .then(
                (result) =>
                    ToolCallRecord(name: tool.name, args: args, result: result),
              ),
      ]);
      service.appendEvidence(surfaceId, records);
    } catch (_) {
      service.setEvidenceLoading(surfaceId, loading: false);
    }
  }

  Future<void> submitMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    // El lock se toma de forma sincrónica, antes de cualquier `await`, para
    // que dos envíos concurrentes nunca pasen ambos el chequeo. `isWaiting`
    // se prende en el mismo instante para que la UI refleje exactamente la
    // ventana en la que el guard está tomado.
    if (!_sendGuard.tryAcquire()) return;
    // Con el lock ya tomado: la pantalla pendiente es de esta pregunta.
    final screenContext = _screenForTurn();
    state = state.copyWith(clearError: true, isWaiting: true);
    _setActivity(TurnActivity.thinking);

    try {
      _ensureService();
      final service = _service!;
      final subscription = ref.read(subscriptionProvider.notifier);
      // La cuota ya no se chequea ni se descuenta acá: la aplica el proxy
      // `ai-chat` (una consulta por turno, al responder) y, si no hay,
      // rechaza el turno con un error tipado (ver `ProxyLimitException`).
      // El refresh sigue: el plan con el que se habilitan las tools tiene
      // que ser el actual (p. ej. recién cambiado por el webhook).
      final data = _data ??= ref.read(assistantDepsProvider).createData();
      // Todo lo que el turno necesita antes de la primera ronda se pide a la
      // vez: son lecturas independientes, y en serie sumaban 0,5-1,5 s por
      // consulta (ver docs/superpowers/research/2026-10-15-porty-latencia.md).
      final newsProviderF = data.newsProvider();
      final closedF = _fetchClosedPositions();
      final profileF = _profileForTurn();
      final memoriesF = _memoriesForTurn();
      final goalsF = _goalsForTurn();
      final streamingF = _streamingForTurn();
      await Future.wait<Object?>([
        subscription.refresh(),
        streamingF,
        newsProviderF,
        closedF,
        profileF,
        memoriesF,
        goalsF,
      ]);

      final ctx = AssistantToolContext(
        tier: ref.read(subscriptionProvider).tier,
        data: data,
        newsProvider: await newsProviderF,
        summary: ref.read(homeProvider).summary,
        history: ref.read(homeProvider).history,
        closedPositions: await closedF,
        loadInvestorProfile:
            () => ref.read(investorProfileProvider.notifier).refresh(),
        investorProfile: await profileF,
        actionsThisConversation: [
          for (final MapEntry(key: id, value: progress)
              in state.actionProposals.entries)
            progress.toBrief(id),
        ],
        loadPriceAlerts: _priceAlertsForTool,
        loadAllocationPlan: () async {
          await ref.read(allocationProvider.notifier).load();
          return ref.read(allocationProvider).saved;
        },
        loadWatchlist: _watchlistForTool,
        loadAppSettings: _settingsForTool,
        loadConnectedAccounts: _accountsForTool,
        loadAccountOverview: _accountOverviewForTool,
        pendingRequest: _pendingRequest,
        screenContext: screenContext,
        queriesLeftThisMonth: () {
          final sub = ref.read(subscriptionProvider);
          final left = sub.queriesLimit - sub.queriesUsed;
          return left < 0 ? 0 : left;
        }(),
        loadWeeklyReport: _weeklyReportForTool,
        userMemories: await memoriesF,
        saveMemory: _saveMemory,
        deleteMemory: (id) => ref.read(userMemoryProvider.notifier).remove(id),
        savedGoals: await goalsF,
        saveGoal: (draft) => ref.read(goalsProvider.notifier).save(draft),
      );

      // Análisis Gold de cortesía de la semana: se gasta solo si el modelo
      // pide un análisis completo (ver WeeklyFreeAnalysisGrant).
      final courtesy = WeeklyFreeAnalysisGrant(
        ctx: ctx,
        available: _weeklyFreeAvailable(),
        consume:
            (ticker) =>
                ref.read(weeklyFreeAnalysisProvider.notifier).consume(ticker),
      );

      final surfaceId = GenUiSurfaceIds.assistantTurn(state.turnCounter);
      state = state.copyWith(
        messages: [
          ...state.messages,
          PortfolioQaMessage(role: PortfolioQaRole.user, content: trimmed),
          PortfolioQaMessage(
            role: PortfolioQaRole.assistant,
            surfaceId: surfaceId,
            isStreaming: true,
          ),
        ],
        lastMessage: trimmed,
        turnCounter: state.turnCounter + 1,
      );

      TurnOutcome? outcome;
      try {
        await GenUiRequestTracker.sendAndWait(
          conversation: service.conversation,
          targetSurfaceId: surfaceId,
          send: () async {
            service.streaming = await streamingF;
            outcome = await service.ask(
              question: trimmed,
              portfolioBrief: PortfolioBrief.build(ctx),
              surfaceId: surfaceId,
              tools: AssistantToolset.build(ctx),
              abortCheck:
                  (firstRound) =>
                      AssistantTurnPolicy.paywallFor(firstRound, ctx),
              onActivity: _setActivity,
              beforeRound: courtesy.beforeRound,
              onContent: service.streaming ? _previewSink(surfaceId) : null,
            );
          },
        );
        _pendingRequest = AssistantTurnPolicy.pendingRequest(
          outcome ?? const TurnOutcome([]),
        );
        final notices = AssistantTurnPolicy.noticesFor(
          outcome ?? const TurnOutcome([]),
          profileNudgeAlreadyShown: _profileNudgeShown,
          rememberedFacts: ctx.rememberedFacts,
        );
        if (notices.profileNudge != null) _profileNudgeShown = true;
        _closePreview(surfaceId);
        state = state.copyWith(
          messages: AssistantMessageSync.applyTurnReady(
            state.messages,
            surfaceId,
            showsAdviceDisclaimer: notices.showsDisclaimer,
            profileNudge: notices.profileNudge,
            rememberedFacts: notices.rememberedFacts,
            sources: notices.sources,
          ),
        );
        // El contador del header refleja lo que cobró el servidor.
        unawaited(subscription.refresh());
      } on ProxyLimitException catch (e) {
        // `prompt_not_allowed` en desarrollo = cambió el prompt y falta
        // regenerar la allowlist y desplegar `ai-chat` (ver runbook).
        if (kDebugMode) debugPrint('[Assistant/turn] rejected by proxy: $e');
        state = _applyServerLimit(state, e, surfaceId);
        if (e.isQuota) unawaited(subscription.refresh());
      } on TurnAbortedException catch (e) {
        // Todo lo que pidió el modelo está fuera del plan: igual que antes
        // de las tools, el turno no deja mensajes ni consume cuota — se
        // ofrece el upgrade.
        state = state.copyWith(
          messages: _removeTurn(state.messages, surfaceId),
          paywallReason: e.reason as PaywallReason,
          clearPaywallReason: false,
        );
      } on TimeoutException catch (e) {
        if (kDebugMode) debugPrint('[Assistant/turn] timed out: $e');
        // Falla de generación (el modelo no llegó a tiempo), no de
        // conexión: respuesta de texto simple, sin banner de error.
        state = state.copyWith(
          messages: AssistantMessageSync.applyFallback(
            state.messages,
            surfaceId,
          ),
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[Assistant/turn] failed: $e');
        if (isConnectionFailure(e)) {
          state = state.copyWith(
            error: genUiErrorMessage(e),
            messages: _removeStreamingPlaceholder(state.messages),
          );
        } else {
          // JSON inválido, "interfaz sin componente raíz", etc.: nunca deja
          // al usuario sin respuesta, cae a texto.
          state = state.copyWith(
            messages: AssistantMessageSync.applyFallback(
              state.messages,
              surfaceId,
            ),
          );
        }
      }
    } finally {
      // Fallback, aviso o error: la vista previa (si hubo) no queda colgada.
      if (mounted) _preview.value = null;
      // Se libera siempre, sin importar por qué rama se salió, así el guard
      // y `isWaiting` nunca quedan trabados en `true`.
      _sendGuard.release();
      _setActivity(TurnActivity.idle);
      state = state.copyWith(isWaiting: false);
      final queued = _queuedQuestion;
      _queuedQuestion = null;
      if (queued != null && mounted) {
        unawaited(Future.microtask(() => _submitFromOutside(queued)));
      }
    }
  }

  /// Rechazo del servidor antes de responder: la cuota del mes abre el
  /// paywall (como antes); el tope diario es un aviso discreto en la fila
  /// de la respuesta, no una venta; el resto, el banner de error.
  AssistantState _applyServerLimit(
    AssistantState current,
    ProxyLimitException e,
    String surfaceId,
  ) {
    if (e.isQuota) {
      return current.copyWith(
        messages: _removeTurn(current.messages, surfaceId),
        paywallReason: PaywallReason.quotaExceeded,
        clearPaywallReason: false,
      );
    }
    if (e.isDailyLimit) {
      return current.copyWith(
        messages: [
          for (final m in current.messages)
            m.surfaceId == surfaceId
                ? m.copyWith(
                  isStreaming: false,
                  notice: AssistantNotice.dailyLimit,
                )
                : m,
        ],
      );
    }
    return current.copyWith(
      error: genUiErrorMessage(e),
      messages: _removeStreamingPlaceholder(current.messages),
    );
  }

  // ------------------------------------------------------------ acciones

  /// Lo que el usuario editó en la card del plan [planId], si lo editó.
  Map<String, Object?>? editedPlan(String planId) =>
      _data?.plans.editOf(planId);

  /// El usuario editó (o deshizo, con `null`) el plan [planId] en su card:
  /// queda en la conversación para que Porty parta de ahí ("hacelo en 2
  /// años", la compra mensual, guardarla).
  void editPlan(String planId, Map<String, Object?>? edited) {
    final plans = _data?.plans;
    if (plans == null) return;
    final editedId = edited?[GoalProjectionBuilder.planIdKey];
    if (edited == null || editedId is! String) {
      plans.clearEdit(planId);
    } else {
      plans.recordEdit(planId, editedId, edited);
    }
  }

  /// Guarda una operación que el usuario confirmó en una card
  /// `QaActionProposal`. No pasa por el modelo (no consume cuota): el
  /// modelo solo propuso (ver `ActionTools`).
  ///
  /// Una sola vez por propuesta: el estado pasa a `saving` de forma
  /// sincrónica, antes de cualquier `await`, así un doble toque no guarda
  /// dos veces. Si falla, queda `failed` y se puede reintentar.
  Future<void> executeAction(ActionDraft draft) async {
    final id = draft.proposalId;
    if (!state.actionProgress(id).canConfirm) return;
    _setAction(
      id,
      ActionProposalProgress(ActionProposalStatus.saving, draft: draft),
    );

    // El plan con el que se propuso pudo cambiar (venció, o lo bajó el
    // webhook): se vuelve a mirar antes de escribir.
    try {
      await ref.read(subscriptionProvider.notifier).refresh();
    } catch (_) {}
    if (!mounted) return;
    final tier = ref.read(subscriptionProvider).tier;
    // Seguir un ticker (o tocar la lista) es de la lista de seguimiento
    // (Premium), no una operación de cartera.
    if ((draft.kind == ActionKind.watch ||
            draft.manageOp?.link == ManageLink.watchlist) &&
        PlanMatrix.of(tier).watchlistLimit == 0) {
      _setAction(id, ActionProposalProgress.pending);
      state = state.copyWith(
        paywallReason: PaywallReason.marketDataLocked,
        clearPaywallReason: false,
      );
      return;
    }
    // Las cuentas conectadas son de Premium.
    if (draft.manageOp?.link == ManageLink.broker &&
        !PlanMatrix.allows(tier, PlanFeature.brokerSync)) {
      _setAction(id, ActionProposalProgress.pending);
      state = state.copyWith(
        paywallReason: PaywallReason.brokerSync,
        clearPaywallReason: false,
      );
      return;
    }
    // El plan de cartera es de Premium.
    if (draft.manageOp?.link == ManageLink.allocation &&
        !PlanMatrix.allows(tier, PlanFeature.allocationPlan)) {
      _setAction(id, ActionProposalProgress.pending);
      state = state.copyWith(
        paywallReason: PaywallReason.modeLocked,
        clearPaywallReason: false,
      );
      return;
    }
    // Las alertas no son una operación de cartera: Free tiene una y el tope
    // lo controla la base al crearla.
    if (draft.kind != ActionKind.alert &&
        draft.kind != ActionKind.watch &&
        draft.kind != ActionKind.manage &&
        !PlanMatrix.allows(tier, PlanFeature.portfolioActions)) {
      _setAction(id, ActionProposalProgress.pending);
      state = state.copyWith(
        paywallReason: PaywallReason.modeLocked,
        clearPaywallReason: false,
      );
      return;
    }

    String? error;
    ClosedPosition? closed;
    try {
      error = _invalidDraft(draft);
      if (error == null) {
        final result = await _runAction(draft);
        error = result.error;
        closed = result.closed;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Assistant/action] failed: $e');
      error = _actionFailedMessage;
    }
    if (!mounted) return;
    if (error != null) {
      _setAction(
        id,
        ActionProposalProgress(
          ActionProposalStatus.failed,
          errorMessage: error,
          draft: draft,
        ),
      );
      return;
    }

    _setAction(
      id,
      ActionProposalProgress(
        ActionProposalStatus.done,
        draft: draft,
        closedPosition: closed,
      ),
    );
    ref
        .read(alertProvider.notifier)
        .showSuccess(
          message:
              draft.manageOp?.done(draft.manageTarget) ??
              switch (draft.kind) {
                ActionKind.buy => 'assistant_action_saved_buy',
                ActionKind.sell => 'assistant_action_saved_sell',
                ActionKind.delete => 'assistant_action_saved_delete',
                ActionKind.alert => 'assistant_action_saved_alert',
                ActionKind.watch ||
                ActionKind.manage => 'assistant_action_saved_watch',
              }.tr(namedArgs: {'ticker': draft.ticker}),
        );
    if (draft.kind == ActionKind.alert ||
        draft.kind == ActionKind.watch ||
        draft.kind == ActionKind.manage) {
      return;
    }
    // La Home y el PORTFOLIO_BRIEF del próximo turno ya con la operación.
    try {
      await ref.read(homeProvider.notifier).refresh(silent: true);
    } catch (_) {}
  }

  /// El usuario descartó la propuesta: no se guarda nada. [draft] es lo que
  /// había en la card, para mostrarla resuelta.
  void cancelAction(ActionDraft draft) {
    final id = draft.proposalId;
    if (!state.actionProgress(id).canConfirm) return;
    _setAction(
      id,
      ActionProposalProgress(ActionProposalStatus.cancelled, draft: draft),
    );
  }

  // Fuera de [AssistantState] a propósito, como [_activity]: cambia con cada
  // tecla y no tiene por qué reconstruir el chat. Vive lo que la
  // conversación.
  final _actionForms = <String, ActionForm>{};

  /// Lo que el usuario lleva editado en la card [proposalId], para que
  /// vuelva igual si se desmonta al scrollear (ver `QaActionScope.formOf`).
  ActionForm? actionFormOf(String proposalId) => _actionForms[proposalId];

  void saveActionForm(String proposalId, ActionForm form) {
    _actionForms[proposalId] = form;
  }

  /// Cierre de [ticker] en [date], para la card cuando el usuario cambia la
  /// fecha (misma regla que las tools: ver `ActionPrices.closeOn`).
  Future<double?> actionPriceOn(String ticker, DateTime date) async {
    try {
      final data = _data ??= ref.read(assistantDepsProvider).createData();
      return (await ActionPrices.closeOn(
        data.quoteRepository,
        ticker,
        date,
      )).close;
    } catch (_) {
      return null;
    }
  }

  static const _actionFailedMessage = 'No se pudo guardar. Probá de nuevo.';

  void _setAction(String id, ActionProposalProgress progress) {
    state = state.copyWith(
      actionProposals: {...state.actionProposals, id: progress},
    );
  }

  /// La card ya valida, pero esto es lo último antes de escribir.
  String? _invalidDraft(ActionDraft draft) {
    if (draft.kind == ActionKind.watch) return null;
    if (draft.kind == ActionKind.manage) {
      return draft.manageOp == null ? _actionFailedMessage : null;
    }
    if (draft.kind == ActionKind.alert) {
      final target = draft.alertTarget;
      return target == null || target <= 0 || draft.alertCondition == null
          ? 'Revisá el objetivo de la alerta.'
          : null;
    }
    if (draft.kind == ActionKind.delete) {
      return draft.lotIds.isEmpty ? 'Elegí qué compra borrar.' : null;
    }
    final shares = draft.shares;
    final price = draft.price;
    final date = draft.date;
    if (shares == null || shares <= 0 || price == null || price <= 0) {
      return 'Revisá la cantidad y el precio.';
    }
    if (date == null || date.isAfter(DateTime.now())) {
      return 'Revisá la fecha.';
    }
    return null;
  }

  /// Ejecuta [draft] con los use cases de siempre (los mismos que las
  /// pantallas de alta, cierre y detalle). Devuelve el error para el
  /// usuario, o `null` si salió bien.
  /// Guarda [draft]. `error`: el mensaje para el usuario si falló; `closed`:
  /// en una venta, la posición cerrada que quedó registrada.
  Future<({String? error, ClosedPosition? closed})> _runAction(
    ActionDraft draft,
  ) async {
    String? message(Either<HttpError, Object?> result) => result.fold(
      (e) =>
          e.message?.trim().isNotEmpty == true
              ? e.message
              : _actionFailedMessage,
      (_) => null,
    );

    switch (draft.kind) {
      case ActionKind.buy:
        final error = message(
          await ref
              .read(addPositionUseCaseProvider)
              .call(
                params: AddPositionParams(
                  ticker: draft.ticker,
                  quantity: draft.shares!,
                  purchasePrice: draft.price!,
                  purchaseDate: draft.date!,
                ),
              ),
        );
        return (error: error, closed: null);
      case ActionKind.sell:
        // Con el ticker (no un id de lote) el repositorio vende FIFO entre
        // todas las compras, como estimó la card.
        final result = await ref
            .read(closePositionUseCaseProvider)
            .call(
              params: ClosePositionParams(
                positionId: draft.ticker,
                quantity: draft.shares!,
                closePrice: draft.price!,
                closeDate: draft.date!,
              ),
            );
        return (
          error: message(result),
          closed: result.fold((_) => null, (closed) => closed),
        );
      case ActionKind.delete:
        final delete = ref.read(deletePositionUseCaseProvider);
        for (final lotId in draft.lotIds) {
          final error = message(await delete.call(params: lotId));
          if (error != null) return (error: error, closed: null);
        }
        return (error: null, closed: null);
      case ActionKind.alert:
        return (error: await _createAlert(draft), closed: null);
      case ActionKind.watch:
        return (error: await _follow(draft), closed: null);
      case ActionKind.manage:
        return (error: await _manage(draft), closed: null);
    }
  }

  /// Ejecuta una operación de gestión ([ManageOp]) con los mismos
  /// notifiers que las pantallas. Devuelve el error para el usuario.
  Future<String?> _manage(ActionDraft draft) async {
    final op = draft.manageOp!;
    try {
      switch (op) {
        case ManageOp.unwatch ||
            ManageOp.watchNotifyOn ||
            ManageOp.watchNotifyOff:
          final notifier = ref.read(watchlistProvider.notifier);
          if (!ref.read(watchlistProvider).loaded) await notifier.load();
          final item =
              ref
                  .read(watchlistProvider)
                  .items
                  .where((i) => i.symbol == draft.ticker)
                  .firstOrNull;
          if (item == null) return 'Ya no seguís ${draft.ticker}.';
          if (op == ManageOp.unwatch) {
            await notifier.remove(item);
          } else {
            await notifier.setNotify(item, op == ManageOp.watchNotifyOn);
          }
        case ManageOp.alertPause ||
            ManageOp.alertResume ||
            ManageOp.alertDelete:
          final notifier = ref.read(priceAlertsProvider.notifier);
          await notifier.load();
          final alert =
              ref
                  .read(priceAlertsProvider)
                  .alerts
                  .where((a) => a.id == draft.targetId)
                  .firstOrNull;
          if (alert == null) return 'Esa alerta ya no existe.';
          if (op == ManageOp.alertDelete) {
            await notifier.delete(alert);
          } else {
            await notifier.setActive(alert, active: op == ManageOp.alertResume);
          }
        case ManageOp.goalDelete ||
            ManageOp.goalAchieved ||
            ManageOp.goalHoldings ||
            ManageOp.goalOutsideSavings:
          final goals = ref.read(goalsProvider.notifier);
          await goals.ensureLoaded();
          final id = draft.targetId;
          if (id == null || ref.read(goalsProvider).byId(id) == null) {
            return 'Esa meta ya no existe.';
          }
          final target = draft.manageTarget;
          switch (op) {
            case ManageOp.goalDelete:
              await goals.delete(id);
            case ManageOp.goalAchieved:
              await goals.setStatus(id, GoalStatus.achieved);
            case ManageOp.goalHoldings:
              await goals.setLinkedTickers(id, target.tickers.toSet());
            default:
              await goals.setExternalSavings(id, target.amount ?? 0);
          }
        case ManageOp.allocationSave:
          return await _saveAllocation(draft.manageTarget);
        case ManageOp.settingsChange:
          return await _applySettings(draft.manageTarget.changes);
        case ManageOp.memoryClear:
          await ref.read(userMemoryProvider.notifier).clear();
        case ManageOp.brokerSync || ManageOp.brokerDisconnect:
          return await _brokerAction(draft.manageTarget, op);
      }
      return null;
    } on GoalsFailure {
      return 'No me pude conectar. Probá de nuevo.';
    } on WatchlistFailure {
      return 'No me pude conectar. Probá de nuevo.';
    } on PriceAlertLimitReached catch (e) {
      final limit =
          e.limit ??
          PlanMatrix.of(ref.read(subscriptionProvider).tier).priceAlertLimit;
      return 'Llegaste al máximo de $limit alertas activas de tu plan.';
    }
  }

  /// Suma [draft] a la lista de seguimiento (lo mismo que la pantalla) y,
  /// si el usuario apagó el interruptor, le saca los avisos.
  Future<String?> _follow(ActionDraft draft) async {
    final watchlist = ref.read(watchlistProvider.notifier);
    try {
      if (!ref.read(watchlistProvider).loaded) await watchlist.load();
      if (ref.read(watchlistProvider).contains(draft.ticker)) {
        return 'Ya seguís ${draft.ticker}.';
      }
      final item = await watchlist.add(draft.ticker);
      if (!draft.watchNotify) await watchlist.setNotify(item, false);
      return null;
    } on WatchlistUnknownSymbol {
      return 'No encontré cotización para ${draft.ticker}.';
    } on WatchlistDuplicate {
      return 'Ya seguís ${draft.ticker}.';
    } on WatchlistLimitReached {
      final limit =
          PlanMatrix.of(ref.read(subscriptionProvider).tier).watchlistLimit;
      return 'Llegaste al máximo de $limit tickers de tu plan.';
    } on WatchlistFailure {
      return 'No me pude conectar. Probá de nuevo.';
    }
  }

  /// Actualiza o desconecta eToro o Binance (lo mismo que sus pantallas).
  Future<String?> _brokerAction(ManageTarget target, ManageOp op) async {
    final keep = target.params['keep'] != false;
    if (target.params['broker'] == 'binance') {
      final binance = ref.read(binanceProvider.notifier);
      if (!ref.read(binanceProvider).loaded) await binance.load();
      if (!ref.read(binanceProvider).connection.isConnected) {
        return 'Binance no está conectada.';
      }
      if (op == ManageOp.brokerSync) {
        await binance.sync();
      } else {
        await binance.disconnect(keepAsManual: keep);
      }
      final error = ref.read(binanceProvider).errorType;
      return error == null ? null : binanceErrorMessage(error);
    }
    final etoro = ref.read(etoroConnectionProvider.notifier);
    if (!ref.read(etoroConnectionProvider).loaded) await etoro.load();
    final etoroState = ref.read(etoroConnectionProvider).connection;
    if (op == ManageOp.brokerSync
        ? !etoroState.isConnected
        : !etoroState.hasImportedData) {
      return 'eToro no está conectada.';
    }
    final ok =
        op == ManageOp.brokerSync
            ? await etoro.sync(userInitiated: true)
            : await etoro.disconnect(keepAsManual: keep);
    if (ok) return null;
    final error = ref.read(etoroConnectionProvider).lastActionError;
    return error == null
        ? 'eToro está ocupada. Probá en unos segundos.'
        : EtoroMessages.syncError(error);
  }

  /// Aplica los ajustes de [changes] con los mismos notifiers que Ajustes.
  /// El idioma lo cambia la pantalla (necesita su `BuildContext`).
  Future<String?> _applySettings(Map<String, Object?> changes) async {
    bool? flag(String key) =>
        changes[key] is bool ? changes[key] as bool : null;
    final touchesNotifications = changes.keys.any(
      (key) =>
          key.startsWith('notif') ||
          key == AppSettingKeys.sensitivity ||
          key == AppSettingKeys.quietHours,
    );
    if (touchesNotifications) {
      final prefs = ref.read(notificationPreferencesProvider.notifier);
      if (!ref.read(notificationPreferencesProvider).loaded) {
        await prefs.load();
      }
      int? start;
      int? end;
      final quiet = changes[AppSettingKeys.quietHours];
      if (quiet == 'off') {
        start = 0;
        end = 0;
      } else if (quiet is String) {
        final parts = quiet.split('-');
        int? clock(String v) {
          final hm = v.trim().split(':');
          final h = int.tryParse(hm.first);
          final m = hm.length > 1 ? int.tryParse(hm[1]) : 0;
          return h == null || m == null ? null : h * 60 + m;
        }

        start = parts.isNotEmpty ? clock(parts.first) : null;
        end = parts.length > 1 ? clock(parts[1]) : null;
      }
      await prefs.update(
        (p) => p.copyWith(
          enabled: flag(AppSettingKeys.notifications),
          priceAlerts: flag(AppSettingKeys.priceAlerts),
          bigMoves: flag(AppSettingKeys.bigMoves),
          portfolioMoves: flag(AppSettingKeys.portfolioMoves),
          weeklyReport: flag(AppSettingKeys.weeklyReport),
          earnings: flag(AppSettingKeys.earnings),
          showAmounts: flag(AppSettingKeys.showAmounts),
          bigMoveSensitivity:
              changes[AppSettingKeys.sensitivity] == null
                  ? null
                  : BigMoveSensitivity.parse(
                    changes[AppSettingKeys.sensitivity],
                  ),
          quietStartMinutes: start,
          quietEndMinutes: end,
        ),
      );
      if (ref.read(notificationPreferencesProvider).saveFailed) {
        return 'No pude guardar las notificaciones. Probá de nuevo.';
      }
    }
    final currency = changes[AppSettingKeys.currency];
    if (currency is String) {
      await ref
          .read(displayCurrencyProvider.notifier)
          .set(DisplayCurrency.fromCode(currency));
    }
    final theme = changes[AppSettingKeys.theme];
    if (theme is String) {
      await ref.read(themeModeProvider.notifier).setThemeMode(switch (theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      });
    }
    final haptics = flag(AppSettingKeys.haptics);
    if (haptics != null) {
      await ref.read(hapticsEnabledProvider.notifier).setEnabled(haptics);
    }
    return null;
  }

  /// Guarda el plan de cartera de [target] sobre el que ya tiene (lo que
  /// no viene en `params` queda como estaba).
  Future<String?> _saveAllocation(ManageTarget target) async {
    final notifier = ref.read(allocationProvider.notifier);
    await notifier.load();
    final saved = ref.read(allocationProvider).saved;
    final p = target.params;
    final threshold = (p['threshold'] as num?)?.toDouble();
    final plan = saved.copyWith(
      targets: target.targets.isEmpty ? null : target.targets,
      driftThreshold: threshold?.clamp(1, 50).toDouble(),
      notify: p['notify'] is bool ? p['notify'] as bool : null,
      frequency:
          p['frequency'] == null
              ? null
              : AllocationAlertFrequency.parse(p['frequency']),
    );
    if (plan.isEmpty) return 'Todavía no tenés un plan: decime qué querés.';
    if (!plan.sumsTo100) return 'El plan tiene que sumar 100%.';
    if (await notifier.save(plan)) return null;
    if (ref.read(allocationProvider).error == AllocationError.locked) {
      state = state.copyWith(
        paywallReason: PaywallReason.modeLocked,
        clearPaywallReason: false,
      );
      return 'El plan de cartera es de Premium.';
    }
    return 'No pude guardar tu plan. Probá de nuevo.';
  }

  /// Crea la alerta de [draft] (la misma que la hoja de la app). Al tope
  /// del plan, ofrece el paywall (si hay un plan con más).
  Future<String?> _createAlert(ActionDraft draft) async {
    try {
      await ref
          .read(priceAlertsProvider.notifier)
          .create(
            PriceAlertDraft(
              symbol: draft.ticker,
              condition: PriceAlertCondition.parse(draft.alertCondition),
              target: draft.alertTarget!,
              referencePrice: draft.price,
              repeatDaily: draft.alertRepeatDaily,
              source: 'porty',
            ),
          );
      return null;
    } on PriceAlertLimitReached catch (e) {
      final tier = ref.read(subscriptionProvider).tier;
      if (tier != SubscriptionTier.gold) {
        state = state.copyWith(
          paywallReason: PaywallReason.priceAlerts,
          clearPaywallReason: false,
        );
      }
      final limit = e.limit ?? PlanMatrix.of(tier).priceAlertLimit;
      return 'Llegaste al máximo de $limit alertas activas de tu plan.';
    } on PriceAlertInvalid {
      return 'Revisá el ticker y el objetivo de la alerta.';
    }
  }

  /// Para list_price_alerts: lo mínimo que necesita el modelo.
  Future<List<Map<String, Object?>>> _watchlistForTool() async {
    final notifier = ref.read(watchlistProvider.notifier);
    if (!ref.read(watchlistProvider).loaded) await notifier.load();
    // Las cotizaciones tardan (precio + historial por ticker): se esperan
    // un rato y, si no llegan todas, la lista sale igual sin ese precio.
    // Antes esperaba todo y con varios tickers pasaba el tope de 8 s de la
    // tool ("no tengo acceso a tu lista").
    try {
      await notifier.refreshQuotes().timeout(_watchlistQuotesWait);
    } on TimeoutException {
      // Lo que llegó, llegó.
    } catch (_) {}
    final state = ref.read(watchlistProvider);
    double? round2(double? v) =>
        v == null ? null : (v * 100).roundToDouble() / 100;
    return [
      for (final item in state.items)
        {
          'ticker': item.symbol,
          'price': state.quotes[item.symbol]?.price,
          'day_change_pct': round2(state.quotes[item.symbol]?.dayChangePct),
          'since_added_pct': round2(
            state.quotes[item.symbol]?.sinceAddedPct(item.addedPrice),
          ),
          'alerts_on': item.notify,
        },
    ];
  }

  static const _watchlistQuotesWait = Duration(seconds: 5);

  /// La acción que el último turno dejó esperando un dato (ver
  /// [AssistantTurnPolicy.pendingRequest]); vive lo que la conversación.
  Map<String, Object?>? _pendingRequest;

  /// Para get_app_settings: la cuenta además de los ajustes.
  Future<Map<String, Object?>> _accountOverviewForTool() async {
    final accounts = await _accountsForTool();
    final sub = ref.read(subscriptionProvider);
    final e = ref.read(etoroConnectionProvider).connection;
    final b = ref.read(binanceProvider).connection;
    String? day(DateTime? d) => d?.toUtc().toIso8601String();
    List<Map<String, Object?>> achieved = const [];
    try {
      await ref.read(goalsProvider.notifier).ensureLoaded();
      achieved = [
        for (final g in ref.read(goalsProvider).goals)
          if (g.status == GoalStatus.achieved)
            {'label': g.label, 'target_amount': g.targetAmount.round()},
      ];
    } catch (_) {}
    return {
      'plan': sub.tier.name,
      'queries_used_this_month': sub.queriesUsed,
      'queries_limit_this_month': sub.queriesLimit,
      'connected_accounts': {
        'etoro': {
          'status': accounts['etoro'],
          if (e.lastSyncAt != null) 'last_sync': day(e.lastSyncAt),
          if (e.lastResult != null) 'imported': e.lastResult!.imported,
        },
        'binance': {
          'status': accounts['binance'],
          if (b.lastSyncAt != null) 'last_sync': day(b.lastSyncAt),
          if (b.lastResult != null) 'imported': b.lastResult!.imported,
        },
      },
      if (achieved.isNotEmpty) 'achieved_goals': achieved,
    };
  }

  /// Para get_weekly_report: el informe de esta semana (sin la serie
  /// diaria, que es para el gráfico). `null` si todavía no está.
  Future<Map<String, Object?>?> _weeklyReportForTool() async {
    final report = ref.read(weeklyReportControllerProvider).report;
    if (report == null) return null;
    return {...report.toJson()}
      ..remove('v')
      ..remove('daily');
  }

  /// Para propose_broker_action: cómo está cada cuenta conectada.
  Future<Map<String, String>> _accountsForTool() async {
    final etoro = ref.read(etoroConnectionProvider.notifier);
    final binance = ref.read(binanceProvider.notifier);
    await Future.wait([
      if (!ref.read(etoroConnectionProvider).loaded) etoro.load(),
      if (!ref.read(binanceProvider).loaded) binance.load(),
    ]);
    final e = ref.read(etoroConnectionProvider).connection;
    final b = ref.read(binanceProvider).connection;
    return {
      'etoro':
          e.needsReconnect
              ? 'reconnect_required'
              : e.isConnected
              ? 'connected'
              : 'not_connected',
      'binance': switch (b.status) {
        BinanceStatus.connected => 'connected',
        BinanceStatus.reconnectRequired => 'reconnect_required',
        BinanceStatus.notConnected => 'not_connected',
      },
    };
  }

  /// Para get_app_settings y propose_settings_change: lo que hay hoy.
  Future<Map<String, Object?>> _settingsForTool() async {
    final prefsNotifier = ref.read(notificationPreferencesProvider.notifier);
    if (!ref.read(notificationPreferencesProvider).loaded) {
      await prefsNotifier.load();
    }
    final p = ref.read(notificationPreferencesProvider).preferences;
    final theme = ref.read(themeModeProvider);
    return {
      AppSettingKeys.notifications: p.enabled,
      AppSettingKeys.priceAlerts: p.priceAlerts,
      AppSettingKeys.bigMoves: p.bigMoves,
      AppSettingKeys.portfolioMoves: p.portfolioMoves,
      AppSettingKeys.weeklyReport: p.weeklyReport,
      AppSettingKeys.earnings: p.earnings,
      AppSettingKeys.showAmounts: p.showAmounts,
      AppSettingKeys.sensitivity: p.bigMoveSensitivity.name,
      AppSettingKeys.quietHours:
          p.hasQuietHours
              ? '${NotificationPreferences.formatClock(p.quietStartMinutes)}-'
                  '${NotificationPreferences.formatClock(p.quietEndMinutes)}'
              : 'off',
      AppSettingKeys.currency: ref.read(displayCurrencyProvider).code,
      AppSettingKeys.theme: switch (theme) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        _ => 'system',
      },
      AppSettingKeys.haptics: ref.read(hapticsEnabledProvider),
      AppSettingKeys.language:
          Intl.getCurrentLocale().startsWith('en') ? 'en' : 'es',
    };
  }

  Future<List<Map<String, Object?>>> _priceAlertsForTool() async {
    final notifier = ref.read(priceAlertsProvider.notifier);
    await notifier.load();
    return [
      for (final a in ref.read(priceAlertsProvider).alerts)
        {
          'id': a.id,
          'symbol': a.symbol,
          'condition': a.condition.storage,
          'target': a.target,
          if (a.referencePrice != null) 'reference_price': a.referencePrice,
          'repeat': a.repeatDaily ? 'daily' : 'once',
          'status': a.status.name,
          if (a.lastPrice != null) 'last_price': a.lastPrice,
          if (a.triggeredAt != null)
            'triggered_at': a.triggeredAt!.toUtc().toIso8601String(),
        },
    ];
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
  /// (que no tiene `surfaceId`). El índice identifica al mismo mensaje de
  /// forma estable: los mensajes solo se agregan al final, y lo único que
  /// se quita es el último turno (placeholder, o el turno entero ante un
  /// paywall) — siempre después de todos los ya revelados.
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

  List<PortfolioQaMessage> _removeStreamingPlaceholder(
    List<PortfolioQaMessage> messages,
  ) {
    if (messages.isEmpty || !messages.last.isStreaming) return messages;
    return messages.sublist(0, messages.length - 1);
  }

  /// Quita el placeholder de [surfaceId] y el mensaje de usuario anterior.
  List<PortfolioQaMessage> _removeTurn(
    List<PortfolioQaMessage> messages,
    String surfaceId,
  ) {
    final index = messages.lastIndexWhere((m) => m.surfaceId == surfaceId);
    if (index < 1) return messages;
    return [...messages.sublist(0, index - 1), ...messages.sublist(index + 1)];
  }

  /// El perfil de inversor para PORTFOLIO_BRIEF: el que ya está en memoria
  /// (Ajustes lo carga); si todavía no se leyó, una sola lectura. Nunca
  /// frena el turno: si falla, el turno sigue sin perfil.
  Future<InvestorProfile?> _profileForTurn() async {
    final current = ref.read(investorProfileProvider);
    if (current.hasLoaded) return current.profile;
    try {
      return await ref.read(investorProfileProvider.notifier).refresh();
    } catch (_) {
      return null;
    }
  }

  /// Si este turno va con streaming (interruptor del servidor). Nunca
  /// frena el turno: si falla, sin streaming.
  Future<bool> _streamingForTurn() async {
    final enabled = ref.read(assistantDepsProvider).streamingEnabled;
    if (enabled == null) return false;
    try {
      return await enabled();
    } catch (_) {
      return false;
    }
  }

  /// La memoria de Porty para PORTFOLIO_BRIEF: una sola lectura por
  /// conversación (las tools la mantienen al día). Nunca frena el turno.
  Future<List<UserMemory>> _memoriesForTurn() async {
    try {
      return await ref.read(userMemoryProvider.notifier).ensureLoaded();
    } catch (_) {
      return const [];
    }
  }

  /// Las metas activas para PORTFOLIO_BRIEF (una lectura por conversación;
  /// la pestaña y las tools las mantienen al día). Nunca frena el turno.
  Future<List<UserGoal>> _goalsForTurn() async {
    try {
      await ref.read(goalsProvider.notifier).ensureLoaded();
      return ref.read(goalsProvider).active;
    } catch (_) {
      return const [];
    }
  }

  Future<UserMemory> _saveMemory(
    String content,
    UserMemoryCategory category, {
    String? replacesId,
  }) {
    final notifier = ref.read(userMemoryProvider.notifier);
    return replacesId == null
        ? notifier.add(
          content,
          category: category,
          source: UserMemorySource.porty,
        )
        : notifier.replace(replacesId, content, category: category);
  }

  Future<List<ClosedPosition>> _fetchClosedPositions() async {
    final closedResult =
        await ref.read(getClosedPositionsUseCaseProvider).call();
    return closedResult.fold((_) => <ClosedPosition>[], (list) => list);
  }
}

final assistantProvider = StateNotifierProvider.autoDispose
    .family<AssistantProvider, AssistantState, AssistantArgs>((ref, args) {
      final provider = AssistantProvider(ref: ref, args: args);
      ref.onDispose(provider.disposeResources);
      return provider;
    });

/// El texto de Porty de la respuesta [surfaceId] mientras se escribe.
@immutable
class AnswerPreview {
  const AnswerPreview(this.surfaceId, this.text);

  final String surfaceId;
  final String text;
}

/// Una pregunta tocada fuera del chat y la pantalla desde donde llegó.
typedef _OutsideQuestion = ({String text, PortyScreenContext? screen});
