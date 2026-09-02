import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:genui/genui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/assistant/modes/explore/news_query_detector.dart';
import 'package:portfolio_assistant/features/assistant/modes/plan/plan_goal_saver.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/reliability/snapshot_grounding_validator.dart';
import 'package:portfolio_assistant/features/assistant/routing/intent_router.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_snapshot_builder.dart';
import 'package:portfolio_assistant/features/genui_core/genui_surface_ids.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_flow_screen_helpers.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_request_tracker.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_send_guard.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

class AssistantProvider extends StateNotifier<AssistantState> {
  AssistantProvider({
    required this.ref,
    required AssistantArgs args,
  }) : super(
          AssistantState(
            currentMode: _displayModeFor(args.initialMode),
            messagesByMode: {
              _displayModeFor(args.initialMode): [
                PortfolioQaMessage(
                  role: PortfolioQaRole.assistant,
                  content: _welcomeKeyFor(_displayModeFor(args.initialMode)).tr(),
                ),
              ],
            },
          ),
        ) {
    _initialQuestion = args.initialQuestion;
  }

  final Ref ref;
  final _sendGuard = GenUiSendGuard();
  final _surfaceIds = <String>[];

  // Una conversación (servicio + suscripción a sus eventos) por pestaña, para
  // que cambiar de modo no pierda el contexto que la IA ya tiene de esa
  // pestaña. No se disponen al cambiar de modo, solo en `disposeResources`.
  final Map<AssistantMode, AssistantOpenAiService> _services = {};
  final Map<AssistantMode, GenUiConversationSubscription> _subscriptions = {};

  // Invertir y Planificar se muestran como una sola pestaña ("invest"), pero
  // por debajo siguen siendo dos motores/conversaciones independientes (dos
  // servicios, dos prompts, dos snapshots). `_investPlanEngine` recuerda cuál
  // de los dos atendió el último turno para que un mensaje ambiguo (sin
  // keywords de ninguno de los dos) continúe con el mismo motor en vez de
  // saltar arbitrariamente.
  AssistantMode _investPlanEngine = AssistantMode.invest;

  String? _initialQuestion;

  /// Planificar ya no es una pestaña navegable por separado: su motor vive
  /// adentro de la pestaña Invertir. Cualquier AssistantMode que llegue desde
  /// afuera (deep link, sugerencia vieja) se resuelve a la pestaña visible.
  static AssistantMode _displayModeFor(AssistantMode mode) =>
      mode == AssistantMode.plan ? AssistantMode.invest : mode;

  static String _welcomeKeyFor(AssistantMode mode) {
    switch (mode) {
      case AssistantMode.learn:
        return 'assistant_learn_welcome';
      case AssistantMode.explore:
        return 'assistant_explore_welcome';
      case AssistantMode.invest:
        return 'assistant_invest_welcome';
      case AssistantMode.plan:
        return 'assistant_plan_welcome';
      case AssistantMode.portfolio:
        return 'portfolio_qa_welcome';
    }
  }

  List<String> get chipKeys {
    switch (state.currentMode) {
      case AssistantMode.learn:
        return const [
          'assistant_learn_chip_diversify',
          'assistant_learn_chip_pnl_meaning',
          'assistant_learn_chip_risk',
        ];
      case AssistantMode.portfolio:
        return const [
          'portfolio_qa_chip_today',
          'portfolio_qa_chip_risk',
          'portfolio_qa_chip_pnl',
        ];
      case AssistantMode.explore:
        return const [
          'assistant_explore_chip_nvda',
          'assistant_explore_chip_compare',
          'assistant_explore_chip_week',
        ];
      case AssistantMode.invest:
        // Invertir y Planificar viven en una sola pestaña: se mezclan
        // sugerencias de los dos motores.
        return const [
          'assistant_invest_chip_budget',
          'assistant_plan_chip_retirement',
          'assistant_invest_chip_diversify',
          'assistant_plan_chip_monthly',
        ];
      case AssistantMode.plan:
        return const [
          'assistant_plan_chip_retirement',
          'assistant_plan_chip_emergency',
          'assistant_plan_chip_monthly',
        ];
    }
  }

  AssistantOpenAiService? get service => _services[state.currentMode];

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

    await _ensureServiceForMode(state.currentMode);
    state = state.copyWith(isServiceReady: true);

    final question = _initialQuestion?.trim();
    if (question != null && question.isNotEmpty) {
      await submitMessage(question);
    }
  }

  Future<void> submitMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sendGuard.isInFlight || service == null) return;

    final suggestion = IntentRouter.suggest(
      message: trimmed,
      currentMode: state.currentMode,
    );
    if (suggestion != null) {
      if (!ref
          .read(subscriptionProvider.notifier)
          .canAccessMode(suggestion.suggestedMode)) {
        state = state.copyWith(
          paywallReason: PaywallReason.modeLocked,
          clearPaywallReason: false,
        );
        return;
      }
      state = state.copyWith(
        pendingMessage: trimmed,
        modeSuggestion: suggestion,
      );
      return;
    }

    await sendMessage(trimmed);
  }

  void switchModeAndSend(AssistantMode mode) {
    final resolvedMode = _displayModeFor(mode);
    if (!ref.read(subscriptionProvider.notifier).canAccessMode(resolvedMode)) {
      state = state.copyWith(
        paywallReason: PaywallReason.modeLocked,
        clearPaywallReason: false,
      );
      return;
    }
    final pending = state.pendingMessage;
    state = state.copyWith(
      currentMode: resolvedMode,
      isServiceReady: _services.containsKey(resolvedMode),
      clearModeSuggestion: true,
      clearPendingMessage: true,
    );
    _ensureWelcomeMessage(resolvedMode);
    unawaited(_applyModeAndMaybeSend(resolvedMode, pending));
  }

  void dismissSuggestionAndSend() {
    final pending = state.pendingMessage;
    state = state.copyWith(
      clearModeSuggestion: true,
      clearPendingMessage: true,
    );
    if (pending != null) {
      unawaited(sendMessage(pending));
    }
  }

  void clearPaywall() {
    state = state.copyWith(clearPaywallReason: true);
  }

  Future<void> selectMode(AssistantMode mode) async {
    final resolvedMode = _displayModeFor(mode);
    if (resolvedMode == state.currentMode) return;
    if (!ref.read(subscriptionProvider.notifier).canAccessMode(resolvedMode)) {
      state = state.copyWith(
        paywallReason: PaywallReason.modeLocked,
        clearPaywallReason: false,
      );
      return;
    }
    state = state.copyWith(
      currentMode: resolvedMode,
      isServiceReady: _services.containsKey(resolvedMode),
    );
    _ensureWelcomeMessage(resolvedMode);
    await _ensureServiceForMode(resolvedMode);
    state = state.copyWith(isServiceReady: true);
  }

  void clearErrorAndRetry() {
    final mode = state.currentMode;
    final last = state.lastMessage;
    state = state.copyWith(errorByMode: {...state.errorByMode, mode: null});
    if (last.isNotEmpty) {
      unawaited(sendMessage(last));
    }
  }

  /// Si `mode` nunca se visitó, arranca su conversación con el mensaje de
  /// bienvenida. Si ya tiene historial (o solo el de bienvenida), lo respeta:
  /// cambiar de pestaña no debe pisar ni mezclar la conversación de otra.
  void _ensureWelcomeMessage(AssistantMode mode) {
    if (state.messagesByMode.containsKey(mode)) return;
    state = state.copyWith(
      messagesByMode: {
        ...state.messagesByMode,
        mode: [
          PortfolioQaMessage(
            role: PortfolioQaRole.assistant,
            content: _welcomeKeyFor(mode).tr(),
          ),
        ],
      },
    );
  }

  Future<void> _applyModeAndMaybeSend(
    AssistantMode mode,
    String? pendingMessage,
  ) async {
    await _ensureServiceForMode(mode);
    state = state.copyWith(isServiceReady: true);
    if (pendingMessage != null) {
      await sendMessage(pendingMessage);
    }
  }

  /// [engineMode] es el motor real (invest o plan) que atiende el turno. Sus
  /// eventos de conversación se vuelcan sobre `_displayModeFor(engineMode)`:
  /// plan no tiene lista de mensajes propia, comparte la de invest.
  Future<void> _ensureServiceForMode(AssistantMode engineMode) async {
    if (_services.containsKey(engineMode)) return;
    final service = AssistantOpenAiService.forMode(mode: engineMode);
    _services[engineMode] = service;
    final subscription = GenUiConversationSubscription();
    final displayMode = _displayModeFor(engineMode);
    subscription.listen(
      service.conversation,
      (event) => _onConversationEvent(displayMode, event),
    );
    _subscriptions[engineMode] = subscription;
  }

  void _onConversationEvent(AssistantMode mode, ConversationEvent event) {
    var messages = <PortfolioQaMessage>[...?state.messagesByMode[mode]];
    String? error = state.errorByMode[mode];
    var isWaiting = state.isWaiting;

    if (event case ConversationComponentsUpdated(:final surfaceId)) {
      messages = _markTurnReady(messages, surfaceId);
    }

    GenUiFlowScreenHelpers.handleConversationEvent(
      event: event,
      surfaceIds: _surfaceIds,
      setError: (value) => error = value,
      setWaiting: (value) => isWaiting = value,
      onStateChanged: () {},
    );

    state = state.copyWith(
      messagesByMode: {...state.messagesByMode, mode: messages},
      errorByMode: {...state.errorByMode, mode: error},
      isWaiting: isWaiting,
    );
  }

  List<PortfolioQaMessage> _markTurnReady(
    List<PortfolioQaMessage> messages,
    String surfaceId,
  ) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.surfaceId == surfaceId && message.isStreaming) {
        final updated = [...messages];
        updated[i] = message.copyWith(isStreaming: false);
        return updated;
      }
    }
    return messages;
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    // `displayMode` es la pestaña visible: los mensajes, errores y el
    // surfaceId del turno se guardan bajo esta clave. `engineMode` es el
    // motor que realmente atiende el turno (servicio, snapshot, prompt). Para
    // la mayoría de las pestañas son lo mismo; en la pestaña Invertir (que
    // combina Invertir+Planificar) `engineMode` puede resolver a `plan` sin
    // que la pestaña visible cambie.
    // El modo se fija al entrar y se usa durante todo el turno: si el
    // usuario cambia de pestaña mientras este envío sigue en curso, la
    // respuesta debe seguir cayendo en la conversación que la originó, no en
    // la que esté visible cuando el turno finalmente resuelva.
    final displayMode = state.currentMode;
    final engineMode = _resolveEngineMode(displayMode, trimmed);
    // El lock se toma de forma sincrónica, antes de cualquier `await`, para
    // que no exista una ventana en la que dos envíos concurrentes pasen
    // ambos el chequeo. `isWaiting` se prende en el mismo instante para que
    // la UI (que se deshabilita según `isWaiting`) refleje exactamente la
    // ventana en la que el guard está tomado.
    if (!_sendGuard.tryAcquire()) return;
    state = state.copyWith(
      errorByMode: {...state.errorByMode, displayMode: null},
      isWaiting: true,
    );

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
      final validation = SnapshotGroundingValidator.validate(
        mode: engineMode,
        snapshot: snapshot,
      );

      if (engineMode == AssistantMode.portfolio &&
          validation == SnapshotValidation.noPortfolioData) {
        state = state.copyWith(
          errorByMode: {
            ...state.errorByMode,
            displayMode: 'portfolio_qa_no_positions'.tr(),
          },
        );
        return;
      }

      if (engineMode == AssistantMode.explore &&
          validation == SnapshotValidation.exploreFetchFailed) {
        final tickers = snapshot['explore_tickers'] as Map?;
        final errorKey = tickers == null || tickers.isEmpty
            ? 'assistant_explore_no_ticker'
            : 'assistant_explore_fetch_failed';
        state = state.copyWith(
          errorByMode: {...state.errorByMode, displayMode: errorKey.tr()},
        );
        return;
      }

      if (engineMode == AssistantMode.invest &&
          validation == SnapshotValidation.exploreFetchFailed) {
        state = state.copyWith(
          errorByMode: {
            ...state.errorByMode,
            displayMode: 'assistant_invest_fetch_failed'.tr(),
          },
        );
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
          GenUiSurfaceIds.assistantTurn(displayMode, state.turnCounter);
      final messages = <PortfolioQaMessage>[
        ...?state.messagesByMode[displayMode],
        PortfolioQaMessage(role: PortfolioQaRole.user, content: trimmed),
        PortfolioQaMessage(
          role: PortfolioQaRole.assistant,
          surfaceId: surfaceId,
          isStreaming: true,
        ),
      ];

      state = state.copyWith(
        messagesByMode: {...state.messagesByMode, displayMode: messages},
        lastMessageByMode: {
          ...state.lastMessageByMode,
          displayMode: trimmed,
        },
        turnCounter: state.turnCounter + 1,
      );

      try {
        await GenUiRequestTracker.sendAndWait(
          conversation: targetService.conversation,
          targetSurfaceId: surfaceId,
          send: () => targetService.sendWithSnapshot(
            userQuestion: trimmed,
            portfolioSnapshotJson: snapshotJson,
            surfaceId: surfaceId,
          ),
        );

        state = state.copyWith(
          messagesByMode: {
            ...state.messagesByMode,
            displayMode: _markTurnReady(
              state.messagesByMode[displayMode] ?? const <PortfolioQaMessage>[],
              surfaceId,
            ),
          },
        );

        final weight = SubscriptionPolicy.queryWeight(isNewsQuery: isNews);
        final consumed =
            await ref.read(aiUsageTrackerProvider).recordUsage(weight);
        await ref.read(subscriptionProvider.notifier).refresh();
        if (!consumed) {
          state = state.copyWith(
            paywallReason: PaywallReason.quotaExceeded,
          );
        }
      } on TimeoutException catch (e) {
        state = state.copyWith(
          errorByMode: {
            ...state.errorByMode,
            displayMode: e.message ?? 'GPT tardó demasiado en responder.',
          },
          messagesByMode: {
            ...state.messagesByMode,
            displayMode: _removeStreamingPlaceholder(
              state.messagesByMode[displayMode] ?? const <PortfolioQaMessage>[],
            ),
          },
        );
      } catch (e) {
        state = state.copyWith(
          errorByMode: {
            ...state.errorByMode,
            displayMode: genUiErrorMessage(e),
          },
          messagesByMode: {
            ...state.messagesByMode,
            displayMode: _removeStreamingPlaceholder(
              state.messagesByMode[displayMode] ?? const <PortfolioQaMessage>[],
            ),
          },
        );
      }
    } finally {
      // Se libera siempre, sin importar por qué rama se salió del bloque
      // (paywall, validación fallida, éxito o excepción), así el guard y
      // `isWaiting` nunca quedan trabados en `true`.
      _sendGuard.release();
      state = state.copyWith(isWaiting: false);
    }
  }

  /// Solo la pestaña combinada (`invest`) necesita elegir motor por mensaje;
  /// el resto de las pestañas son su propio motor. Recuerda la elección en
  /// `_investPlanEngine` para que un mensaje ambiguo (sin keywords propias
  /// de ninguno de los dos) continúe con el motor del turno anterior.
  AssistantMode _resolveEngineMode(AssistantMode displayMode, String message) {
    if (displayMode != AssistantMode.invest) return displayMode;
    final resolved = IntentRouter.resolveInvestPlanEngine(
      message: message,
      lastEngine: _investPlanEngine,
    );
    _investPlanEngine = resolved;
    return resolved;
  }

  List<PortfolioQaMessage> _removeStreamingPlaceholder(
    List<PortfolioQaMessage> messages,
  ) {
    if (messages.isEmpty || !messages.last.isStreaming) return messages;
    return messages.sublist(0, messages.length - 1);
  }

  Future<String> _buildSnapshotJson(AssistantMode mode, String trimmed) async {
    if (mode == AssistantMode.portfolio) {
      final summary = ref.read(homeProvider).summary;
      final closedResult =
          await ref.read(getClosedPositionsUseCaseProvider).call();
      final closedPositions = closedResult.fold(
        (_) => <ClosedPosition>[],
        (list) => list,
      );
      return buildSnapshotJson(
        mode: AssistantMode.portfolio,
        summary: summary,
        history: ref.read(homeProvider).history,
        closedPositions: closedPositions,
        quoteRepository: ref.read(quoteRepositoryProvider),
      );
    }

    if (mode == AssistantMode.explore) {
      final summary = ref.read(homeProvider).summary;
      return buildSnapshotJson(
        mode: AssistantMode.explore,
        userMessage: trimmed,
        summary: summary,
        quoteRepository: ref.read(quoteRepositoryProvider),
        enableNewsEnrichment: SubscriptionPolicy.isNewsAllowed(
          ref.read(subscriptionProvider).tier,
        ),
      );
    }

    if (mode == AssistantMode.invest) {
      final summary = ref.read(homeProvider).summary;
      final riskProfile =
          await ref.read(preferenceManagerProvider).getRiskProfile();
      return buildSnapshotJson(
        mode: AssistantMode.invest,
        userMessage: trimmed,
        summary: summary,
        quoteRepository: ref.read(quoteRepositoryProvider),
        riskProfile: riskProfile,
      );
    }

    if (mode == AssistantMode.plan) {
      final summary = ref.read(homeProvider).summary;
      final prefs = ref.read(preferenceManagerProvider);
      final savedGoal = await prefs.getSavedGoal();
      final monthlyContribution = await prefs.getMonthlyContribution();
      return buildSnapshotJson(
        mode: AssistantMode.plan,
        userMessage: trimmed,
        summary: summary,
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
