import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:genui/genui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
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

  String get _welcomeKey => _welcomeKeyFor(state.currentMode);

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

  void disposeResources() {
    _conversationEvents.cancel();
    _service?.dispose();
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
    if (trimmed.isEmpty || _sendGuard.isInFlight || _service == null) return;

    final suggestion = IntentRouter.suggest(
      message: trimmed,
      currentMode: state.currentMode,
    );
    if (suggestion != null) {
      state = state.copyWith(
        pendingMessage: trimmed,
        modeSuggestion: suggestion,
      );
      return;
    }

    await sendMessage(trimmed);
  }

  void switchModeAndSend(AssistantMode mode) {
    final pending = state.pendingMessage;
    state = state.copyWith(
      currentMode: mode,
      clearModeSuggestion: true,
      clearPendingMessage: true,
    );
    _updateWelcomeIfOnlyMessage();
    unawaited(_applyModeAndMaybeSend(mode, pending));
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

  Future<void> selectMode(AssistantMode mode) async {
    if (mode == state.currentMode) return;
    state = state.copyWith(currentMode: mode);
    _updateWelcomeIfOnlyMessage();
    await _initService();
  }

  void clearErrorAndRetry() {
    final last = state.lastMessage;
    state = state.copyWith(clearError: true);
    if (last.isNotEmpty) {
      unawaited(sendMessage(last));
    }
  }

  void _updateWelcomeIfOnlyMessage() {
    final messages = [...state.messages];
    if (messages.length == 1 &&
        messages.first.role == PortfolioQaRole.assistant &&
        !messages.first.isStreaming) {
      messages[0] = PortfolioQaMessage(
        role: PortfolioQaRole.assistant,
        content: _welcomeKey.tr(),
      );
      state = state.copyWith(messages: messages);
    }
  }

  Future<void> _applyModeAndMaybeSend(
    AssistantMode mode,
    String? pendingMessage,
  ) async {
    await _initService();
    if (pendingMessage != null) {
      await sendMessage(pendingMessage);
    }
  }

  Future<void> _initService() async {
    _conversationEvents.cancel();
    _service?.dispose();
    _service = AssistantOpenAiService.forMode(mode: state.currentMode);
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
    if (trimmed.isEmpty || _sendGuard.isInFlight || _service == null) return;

    final snapshotJson = await _buildSnapshotJson(trimmed);
    final snapshot = jsonDecode(snapshotJson) as Map<String, dynamic>;
    final validation = SnapshotGroundingValidator.validate(
      mode: state.currentMode,
      snapshot: snapshot,
    );

    if (state.currentMode == AssistantMode.portfolio &&
        validation == SnapshotValidation.noPortfolioData) {
      state = state.copyWith(error: 'portfolio_qa_no_positions'.tr());
      return;
    }

    if (state.currentMode == AssistantMode.explore &&
        validation == SnapshotValidation.exploreFetchFailed) {
      final tickers = snapshot['explore_tickers'] as Map?;
      final errorKey = tickers == null || tickers.isEmpty
          ? 'assistant_explore_no_ticker'
          : 'assistant_explore_fetch_failed';
      state = state.copyWith(error: errorKey.tr());
      return;
    }

    if (state.currentMode == AssistantMode.invest &&
        validation == SnapshotValidation.exploreFetchFailed) {
      state = state.copyWith(error: 'assistant_invest_fetch_failed'.tr());
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
    final messages = [
      ...state.messages,
      PortfolioQaMessage(role: PortfolioQaRole.user, content: trimmed),
      PortfolioQaMessage(
        role: PortfolioQaRole.assistant,
        surfaceId: surfaceId,
        isStreaming: true,
      ),
    ];

    state = state.copyWith(
      clearError: true,
      isWaiting: true,
      messages: messages,
      lastMessage: trimmed,
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
