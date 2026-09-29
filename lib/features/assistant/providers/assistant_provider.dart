import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_deps.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_toolset.dart';
import 'package:portfolio_assistant/features/assistant/tools/portfolio_tools.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_message_sync.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_flow_screen_helpers.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_request_tracker.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_send_guard.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_surface_readiness.dart';
import 'package:portfolio_assistant/features/investor_profile/providers/investor_profile_provider.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
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

    final summary = ref.read(homeProvider).summary;
    if (summary == null) {
      await ref.read(homeProvider.notifier).refresh();
    }

    _ensureService();
    state = state.copyWith(isServiceReady: true);

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

      final quotaPaywall = await subscription.checkQuotaAllowed();
      if (quotaPaywall != null) {
        state = state.copyWith(
          paywallReason: quotaPaywall,
          clearPaywallReason: false,
        );
        return;
      }

      final ctx = AssistantToolContext(
        tier: ref.read(subscriptionProvider).tier,
        data: _data ??= ref.read(assistantDepsProvider).createData(),
        summary: ref.read(homeProvider).summary,
        history: ref.read(homeProvider).history,
        closedPositions: await _fetchClosedPositions(),
        loadInvestorProfile:
            () => ref.read(investorProfileProvider.notifier).refresh(),
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
        final consumed = await ref
            .read(aiUsageTrackerProvider)
            .recordUsage(
              AssistantTurnPolicy.quotaWeight(outcome ?? const TurnOutcome([])),
            );
        await subscription.refresh();
        if (!consumed) {
          state = state.copyWith(paywallReason: PaywallReason.quotaExceeded);
        }
      } on TurnAbortedException catch (e) {
        // Todo lo que pidió el modelo está fuera del plan: igual que antes
        // de las tools, el turno no deja mensajes ni consume cuota — se
        // ofrece el upgrade.
        state = state.copyWith(
          messages: _removeTurn(state.messages, surfaceId),
          paywallReason: e.reason as PaywallReason,
          clearPaywallReason: false,
        );
      } on TimeoutException {
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
