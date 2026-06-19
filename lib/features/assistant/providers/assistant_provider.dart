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
import 'package:portfolio_assistant/features/assistant/states/mode_chat_session.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
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
  }) : super(
          AssistantState(
            currentMode: args.initialMode,
            messages: [
              PortfolioQaMessage(
                role: PortfolioQaRole.assistant,
                content: _welcomeKeyFor(args.initialMode).tr(),
              ),
            ],
          ),
        ) {
    _initialQuestion = args.initialQuestion;
  }

  final Ref ref;
  final _sendGuard = GenUiSendGuard();
  final _conversationEvents = GenUiConversationSubscription();
  final _surfaceIds = <String>[];
  final _sessionsByMode = <AssistantMode, ModeChatSession>{};
  final _servicesByMode = <AssistantMode, AssistantOpenAiService>{};
  final _surfaceIdsByMode = <AssistantMode, List<String>>{};

  AssistantOpenAiService? _service;
  String? _initialQuestion;

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
        return const [
          'assistant_invest_chip_budget',
          'assistant_invest_chip_diversify',
          'assistant_invest_chip_concentration',
        ];
      case AssistantMode.plan:
        return const [
          'assistant_plan_chip_retirement',
          'assistant_plan_chip_emergency',
          'assistant_plan_chip_monthly',
        ];
    }
  }

  AssistantOpenAiService? get service => _service;

  bool get isSendInFlight => _sendGuard.isInFlight;

  bool get isInputBlocked => state.isWaiting || isSendInFlight;

  void disposeResources() {
    _conversationEvents.cancel();
    for (final service in _servicesByMode.values) {
      service.dispose();
    }
    _servicesByMode.clear();
    _service = null;
  }

  Future<void> bootstrap() async {
    if (state.bootstrapped) return;

    state = state.copyWith(bootstrapped: true);

    final summary = ref.read(homeProvider).summary;
    if (summary == null) {
      await ref.read(homeProvider.notifier).refresh();
    }

    await _initService();

    final question = _initialQuestion?.trim();
    if (question != null && question.isNotEmpty) {
      await submitMessage(question);
    }
  }

  Future<void> submitMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _service == null) return;

    if (isInputBlocked) {
      state = state.copyWith(error: 'assistant_send_in_progress'.tr());
      return;
    }

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
      state = state.copyWith(modeSuggestion: suggestion);
    }

    await sendMessage(trimmed);
  }

  Future<void> switchModeAndSend(AssistantMode mode) async {
    if (!ref.read(subscriptionProvider.notifier).canAccessMode(mode)) {
      state = state.copyWith(
        paywallReason: PaywallReason.modeLocked,
        clearPaywallReason: false,
      );
      return;
    }
    await _changeMode(mode, clearModeSuggestion: true);
  }

  void dismissModeSuggestion() {
    state = state.copyWith(clearModeSuggestion: true);
  }

  void clearPaywall() {
    state = state.copyWith(clearPaywallReason: true);
  }

  Future<void> selectMode(AssistantMode mode) async {
    if (mode == state.currentMode) return;
    if (!ref.read(subscriptionProvider.notifier).canAccessMode(mode)) {
      state = state.copyWith(
        paywallReason: PaywallReason.modeLocked,
        clearPaywallReason: false,
      );
      return;
    }
    await _changeMode(mode);
  }

  void clearErrorAndRetry() {
    final last = state.lastMessage;
    state = state.copyWith(clearError: true);
    if (last.isNotEmpty) {
      unawaited(sendMessage(last));
    }
  }

  Future<void> _changeMode(
    AssistantMode mode, {
    bool clearModeSuggestion = false,
  }) async {
    _persistCurrentModeSession();

    final restored = _sessionsByMode[mode] ?? _defaultSessionFor(mode);

    _surfaceIds
      ..clear()
      ..addAll(_surfaceIdsByMode[mode] ?? const []);

    state = state.copyWith(
      currentMode: mode,
      messages: restored.messages,
      turnCounter: restored.turnCounter,
      lastMessage: restored.lastMessage,
      isWaiting: false,
      clearError: true,
      clearModeSuggestion: clearModeSuggestion,
    );
    await _initService();
  }

  void _persistCurrentModeSession() {
    final messages = ModeChatSession.sanitizeMessages(state.messages);
    _sessionsByMode[state.currentMode] = ModeChatSession(
      messages: messages,
      turnCounter: state.turnCounter,
      lastMessage: state.lastMessage,
    );
    _surfaceIdsByMode[state.currentMode] = List<String>.from(_surfaceIds);
  }

  ModeChatSession _defaultSessionFor(AssistantMode mode) {
    return ModeChatSession(
      messages: [_welcomeMessageFor(mode)],
    );
  }

  PortfolioQaMessage _welcomeMessageFor(AssistantMode mode) {
    return PortfolioQaMessage(
      role: PortfolioQaRole.assistant,
      content: _welcomeKeyFor(mode).tr(),
    );
  }

  Future<void> _initService() async {
    _conversationEvents.cancel();
    final mode = state.currentMode;
    _service = _servicesByMode.putIfAbsent(
      mode,
      () => AssistantOpenAiService.forMode(mode: mode),
    );
    _conversationEvents.listen(
      _service!.conversation,
      _onConversationEvent,
    );
    state = state.copyWith(isServiceReady: true);
  }

  void _onConversationEvent(ConversationEvent event) {
    var messages = [...state.messages];
    String? error = state.error;
    var isWaiting = state.isWaiting;

    if (event case ConversationComponentsUpdated(
      :final surfaceId,
      :final definition,
    )) {
      if (GenUiSurfaceReadiness.hasRootComponent(definition)) {
        messages = _markTurnReady(messages, surfaceId);
      }
    }

    if (event is ConversationError) {
      error = genUiErrorMessage(event.error);
      isWaiting = false;
    } else {
      GenUiFlowScreenHelpers.handleConversationEvent(
        event: event,
        surfaceIds: _surfaceIds,
        setError: (value) => error = value,
        onStateChanged: () {},
      );
    }

    state = state.copyWith(
      messages: messages,
      error: error,
      isWaiting: isWaiting,
      clearError: error == null,
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
    if (trimmed.isEmpty || _service == null) return;

    if (isInputBlocked) {
      state = state.copyWith(error: 'assistant_send_in_progress'.tr());
      return;
    }

    state = state.copyWith(isWaiting: true, clearError: true);

    final userMessage = PortfolioQaMessage(
      role: PortfolioQaRole.user,
      content: trimmed,
    );
    state = state.copyWith(
      messages: [
        ...state.messages,
        userMessage,
        const PortfolioQaMessage(
          role: PortfolioQaRole.assistant,
          isStreaming: true,
        ),
      ],
      lastMessage: trimmed,
    );

    final isNews =
        state.currentMode == AssistantMode.explore && isNewsQuery(trimmed);
    await ref.read(subscriptionProvider.notifier).refresh();
    final paywall = await ref.read(subscriptionProvider.notifier).checkQueryAllowed(
      mode: state.currentMode,
      isNewsQuery: isNews,
    );
    if (paywall != null) {
      state = state.copyWith(
        paywallReason: paywall,
        clearPaywallReason: false,
        isWaiting: false,
        messages: _removeStreamingPlaceholder(state.messages),
      );
      return;
    }

    final snapshotJson = await _buildSnapshotJson(trimmed);
    final snapshot = jsonDecode(snapshotJson) as Map<String, dynamic>;
    final validation = SnapshotGroundingValidator.validate(
      mode: state.currentMode,
      snapshot: snapshot,
    );

    if (state.currentMode == AssistantMode.portfolio &&
        validation == SnapshotValidation.noPortfolioData) {
      state = state.copyWith(
        error: 'portfolio_qa_no_positions'.tr(),
        isWaiting: false,
        messages: _removeStreamingPlaceholder(state.messages),
      );
      return;
    }

    if (state.currentMode == AssistantMode.explore &&
        validation == SnapshotValidation.exploreFetchFailed) {
      final tickers = snapshot['explore_tickers'] as Map?;
      final errorKey = tickers == null || tickers.isEmpty
          ? 'assistant_explore_no_ticker'
          : 'assistant_explore_fetch_failed';
      state = state.copyWith(
        error: errorKey.tr(),
        isWaiting: false,
        messages: _removeStreamingPlaceholder(state.messages),
      );
      return;
    }

    if (state.currentMode == AssistantMode.invest &&
        validation == SnapshotValidation.exploreFetchFailed) {
      state = state.copyWith(
        error: 'assistant_invest_fetch_failed'.tr(),
        isWaiting: false,
        messages: _removeStreamingPlaceholder(state.messages),
      );
      return;
    }

    if (state.currentMode == AssistantMode.plan) {
      await PlanGoalSaver.persistIfRequested(
        prefs: ref.read(preferenceManagerProvider),
        snapshot: snapshot,
        userMessage: trimmed,
      );
    }

    final surfaceId =
        GenUiSurfaceIds.assistantTurn(state.currentMode, state.turnCounter);
    final messages = [...state.messages];
    if (messages.isNotEmpty && messages.last.isStreaming) {
      messages[messages.length - 1] = PortfolioQaMessage(
        role: PortfolioQaRole.assistant,
        surfaceId: surfaceId,
        isStreaming: true,
      );
    } else {
      messages.add(
        PortfolioQaMessage(
          role: PortfolioQaRole.assistant,
          surfaceId: surfaceId,
          isStreaming: true,
        ),
      );
    }

    state = state.copyWith(
      messages: messages,
      turnCounter: state.turnCounter + 1,
    );

    await _sendGuard.run(() async {
      try {
        await GenUiRequestTracker.sendAndWait(
          conversation: _service!.conversation,
          targetSurfaceId: surfaceId,
          send: () => _service!.sendWithSnapshot(
            userQuestion: trimmed,
            portfolioSnapshotJson: snapshotJson,
            surfaceId: surfaceId,
          ),
        );

        final readyMessages = _markTurnReady(state.messages, surfaceId);
        state = state.copyWith(
          messages: readyMessages,
          isWaiting: false,
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
          error: e.message ?? 'GPT tardó demasiado en responder.',
          isWaiting: false,
          messages: _removeStreamingPlaceholder(state.messages),
        );
      } catch (e) {
        state = state.copyWith(
          error: genUiErrorMessage(e),
          isWaiting: false,
          messages: _removeStreamingPlaceholder(state.messages),
        );
      }
    });
  }

  List<PortfolioQaMessage> _removeStreamingPlaceholder(
    List<PortfolioQaMessage> messages,
  ) {
    if (messages.isEmpty || !messages.last.isStreaming) return messages;
    return messages.sublist(0, messages.length - 1);
  }

  Future<String> _buildSnapshotJson(String trimmed) async {
    if (state.currentMode == AssistantMode.portfolio) {
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

    if (state.currentMode == AssistantMode.explore) {
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

    if (state.currentMode == AssistantMode.invest) {
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

    if (state.currentMode == AssistantMode.plan) {
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

    return buildSnapshotJson(mode: state.currentMode);
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
