import 'dart:async';

import 'package:dartz/dartz.dart' show Either;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
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
import 'package:portfolio_assistant/features/assistant/tools/market_tools.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_deps.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/assistant/tools/action_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_toolset.dart';
import 'package:portfolio_assistant/features/assistant/tools/portfolio_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/weekly_free_analysis_grant.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_message_sync.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_flow_screen_helpers.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_request_tracker.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_send_guard.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_surface_readiness.dart';
import 'package:portfolio_assistant/features/investor_profile/providers/investor_profile_provider.dart';
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
    _initialQuestion = args.initialQuestion;
  }

  final Ref ref;
  final _sendGuard = GenUiSendGuard();
  final _surfaceIds = <String>[];

  AssistantOpenAiService? _service;
  GenUiConversationSubscription? _subscription;
  AssistantDataSources? _data;

  String? _initialQuestion;

  // El aviso de completar/revisar el perfil de inversor sale una sola vez
  // por conversación — ver `AssistantTurnPolicy.noticesFor`.
  bool _profileNudgeShown = false;

  static const List<String> _starterChipKeys = [
    'portfolio_qa_chip_today',
    'assistant_learn_chip_diversify',
    'assistant_explore_chip_nvda',
    'assistant_invest_chip_budget',
  ];

  /// Sugerencias iniciales, una de cada tipo de pregunta.
  List<String> get chipKeys => _starterChipKeys;

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

  @override
  void dispose() {
    _activity.dispose();
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

    _ensureService();
    state = state.copyWith(isServiceReady: true);
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

    final question = _initialQuestion?.trim();
    if (question != null && question.isNotEmpty) {
      await submitMessage(question);
    }
  }

  void _ensureService() {
    if (_service != null) return;
    final service = ref.read(assistantDepsProvider).createService();
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
      final ctx = AssistantToolContext(
        tier: tier,
        data: _data ??= ref.read(assistantDepsProvider).createData(),
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
      await subscription.refresh();

      final ctx = AssistantToolContext(
        tier: ref.read(subscriptionProvider).tier,
        data: _data ??= ref.read(assistantDepsProvider).createData(),
        summary: ref.read(homeProvider).summary,
        history: ref.read(homeProvider).history,
        closedPositions: await _fetchClosedPositions(),
        loadInvestorProfile:
            () => ref.read(investorProfileProvider.notifier).refresh(),
        investorProfile: await _profileForTurn(),
        actionsThisConversation: [
          for (final MapEntry(key: id, value: progress)
              in state.actionProposals.entries)
            progress.toBrief(id),
        ],
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
            );
          },
        );
        final notices = AssistantTurnPolicy.noticesFor(
          outcome ?? const TurnOutcome([]),
          profileNudgeAlreadyShown: _profileNudgeShown,
        );
        if (notices.profileNudge != null) _profileNudgeShown = true;
        state = state.copyWith(
          messages: AssistantMessageSync.applyTurnReady(
            state.messages,
            surfaceId,
            showsAdviceDisclaimer: notices.showsDisclaimer,
            profileNudge: notices.profileNudge,
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
      // Se libera siempre, sin importar por qué rama se salió, así el guard
      // y `isWaiting` nunca quedan trabados en `true`.
      _sendGuard.release();
      _setActivity(TurnActivity.idle);
      state = state.copyWith(isWaiting: false);
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
    if (!PlanMatrix.allows(tier, PlanFeature.portfolioActions)) {
      _setAction(id, ActionProposalProgress.pending);
      state = state.copyWith(
        paywallReason: PaywallReason.modeLocked,
        clearPaywallReason: false,
      );
      return;
    }

    String? error;
    try {
      error = _invalidDraft(draft) ?? await _runAction(draft);
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

    _setAction(id, ActionProposalProgress(ActionProposalStatus.done, draft: draft));
    ref
        .read(alertProvider.notifier)
        .showSuccess(
          message: switch (draft.kind) {
            ActionKind.buy => 'assistant_action_saved_buy',
            ActionKind.sell => 'assistant_action_saved_sell',
            ActionKind.delete => 'assistant_action_saved_delete',
          }.tr(namedArgs: {'ticker': draft.ticker}),
        );
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
      return (await ActionPrices.closeOn(data.quoteRepository, ticker, date))
          .close;
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
  Future<String?> _runAction(ActionDraft draft) async {
    String? message(Either<HttpError, Object?> result) => result.fold(
      (e) =>
          e.message?.trim().isNotEmpty == true
              ? e.message
              : _actionFailedMessage,
      (_) => null,
    );

    switch (draft.kind) {
      case ActionKind.buy:
        return message(
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
      case ActionKind.sell:
        // Con el ticker (no un id de lote) el repositorio vende FIFO entre
        // todas las compras, como estimó la card.
        return message(
          await ref
              .read(closePositionUseCaseProvider)
              .call(
                params: ClosePositionParams(
                  positionId: draft.ticker,
                  quantity: draft.shares!,
                  closePrice: draft.price!,
                  closeDate: draft.date!,
                ),
              ),
        );
      case ActionKind.delete:
        final delete = ref.read(deletePositionUseCaseProvider);
        for (final lotId in draft.lotIds) {
          final error = message(await delete.call(params: lotId));
          if (error != null) return error;
        }
        return null;
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
