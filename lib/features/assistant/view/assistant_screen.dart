import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/genui_core/genui_surface_ids.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_flow_screen_helpers.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_request_tracker.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_send_guard.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/use_cases/get_closed_positions_use_case.dart';
import 'package:portfolio_assistant/features/assistant/reliability/snapshot_grounding_validator.dart';
import 'package:portfolio_assistant/features/assistant/routing/intent_router.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_snapshot_builder.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/mode_chip_bar.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/mode_switch_suggestion.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/portfolio_qa_assistant_surface.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/portfolio_qa_chat_bubble.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/portfolio_qa_disclaimer_banner.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

class AssistantScreen extends StatefulHookConsumerWidget {
  const AssistantScreen({
    super.key,
    this.initialMode = AssistantMode.portfolio,
    this.initialQuestion,
  });

  final AssistantMode initialMode;
  final String? initialQuestion;

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends BaseStatefulWidget<AssistantScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _sendGuard = GenUiSendGuard();
  final _conversationEvents = GenUiConversationSubscription();
  final _surfaceIds = <String>[];

  AssistantOpenAiService? _service;

  final List<PortfolioQaMessage> _messages = [];
  String? _error;
  bool _isWaiting = false;
  bool _bootstrapped = false;
  int _turnCounter = 0;
  String _lastMessage = '';
  late AssistantMode _currentMode;
  ModeSuggestion? _modeSuggestion;
  String? _pendingMessage;

  List<String> get _chipKeys {
    switch (_currentMode) {
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
          'portfolio_qa_chip_today',
          'portfolio_qa_chip_risk',
          'portfolio_qa_chip_pnl',
        ];
    }
  }

  String get _welcomeKey {
    switch (_currentMode) {
      case AssistantMode.learn:
        return 'assistant_learn_welcome';
      case AssistantMode.explore:
        return 'assistant_explore_welcome';
      case AssistantMode.invest:
        return 'assistant_invest_welcome';
      case AssistantMode.portfolio:
      case AssistantMode.plan:
        return 'portfolio_qa_welcome';
    }
  }

  @override
  void initState() {
    _currentMode = widget.initialMode;
    super.initState();
    _messages.add(
      PortfolioQaMessage(
        role: PortfolioQaRole.assistant,
        content: _welcomeKey.tr(),
      ),
    );
    runAfterPostFrameCallback(_bootstrap);
  }

  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    final summary = ref.read(homeProvider).summary;
    if (summary == null) {
      await ref.read(homeProvider.notifier).refresh();
    }

    await _initService();

    final question = widget.initialQuestion?.trim();
    if (question != null && question.isNotEmpty) {
      await _submitMessage(question);
    }
  }

  Future<void> _submitMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sendGuard.isInFlight || _service == null) return;

    final suggestion = IntentRouter.suggest(
      message: trimmed,
      currentMode: _currentMode,
    );
    if (suggestion != null) {
      setState(() {
        _pendingMessage = trimmed;
        _modeSuggestion = suggestion;
      });
      return;
    }

    await _sendMessage(trimmed);
  }

  void _switchModeAndSend(AssistantMode mode) {
    final pending = _pendingMessage;
    setState(() {
      _currentMode = mode;
      _modeSuggestion = null;
      _pendingMessage = null;
      _updateWelcomeIfOnlyMessage();
    });
    unawaited(_applyModeAndMaybeSend(mode, pending));
  }

  void _updateWelcomeIfOnlyMessage() {
    if (_messages.length == 1 &&
        _messages.first.role == PortfolioQaRole.assistant &&
        !_messages.first.isStreaming) {
      _messages[0] = PortfolioQaMessage(
        role: PortfolioQaRole.assistant,
        content: _welcomeKey.tr(),
      );
    }
  }

  Future<void> _applyModeAndMaybeSend(
    AssistantMode mode,
    String? pendingMessage,
  ) async {
    await _initService();
    if (pendingMessage != null) {
      await _sendMessage(pendingMessage);
    }
  }

  void _dismissSuggestionAndSend() {
    final pending = _pendingMessage;
    setState(() {
      _modeSuggestion = null;
      _pendingMessage = null;
    });
    if (pending != null) {
      unawaited(_sendMessage(pending));
    }
  }

  Future<void> _rebuildCatalogForMode() async {
    await _initService();
  }

  Future<void> _initService() async {
    _conversationEvents.cancel();
    _service?.dispose();
    _service = AssistantOpenAiService.forMode(mode: _currentMode);

    _conversationEvents.listen(_service!.conversation, _onConversationEvent);

    if (mounted) setState(() {});
  }

  void _onConversationEvent(ConversationEvent event) {
    if (!mounted) return;
    var shouldRebuild = false;

    if (event case ConversationComponentsUpdated(:final surfaceId)) {
      _markTurnReady(surfaceId);
      shouldRebuild = true;
    }

    GenUiFlowScreenHelpers.handleConversationEvent(
      event: event,
      surfaceIds: _surfaceIds,
      setError: (value) => _error = value,
      setWaiting: (value) => _isWaiting = value,
      onStateChanged: () => shouldRebuild = true,
    );

    if (shouldRebuild) setState(() {});
  }

  void _markTurnReady(String surfaceId) {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final message = _messages[i];
      if (message.surfaceId == surfaceId && message.isStreaming) {
        _messages[i] = message.copyWith(isStreaming: false);
        return;
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _conversationEvents.cancel();
    _service?.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sendGuard.isInFlight || _service == null) return;

    final String snapshotJson;
    if (_currentMode == AssistantMode.portfolio) {
      final summary = ref.read(homeProvider).summary;
      final closedResult =
          await ref.read(getClosedPositionsUseCaseProvider).call();
      final closedPositions = closedResult.fold(
        (_) => <ClosedPosition>[],
        (list) => list,
      );
      snapshotJson = await buildSnapshotJson(
        mode: AssistantMode.portfolio,
        summary: summary,
        history: ref.read(homeProvider).history,
        closedPositions: closedPositions,
        quoteRepository: ref.read(quoteRepositoryProvider),
      );
    } else if (_currentMode == AssistantMode.explore) {
      final summary = ref.read(homeProvider).summary;
      snapshotJson = await buildSnapshotJson(
        mode: AssistantMode.explore,
        userMessage: trimmed,
        summary: summary,
        quoteRepository: ref.read(quoteRepositoryProvider),
      );
    } else if (_currentMode == AssistantMode.invest) {
      final summary = ref.read(homeProvider).summary;
      final riskProfile =
          await ref.read(preferenceManagerProvider).getRiskProfile();
      snapshotJson = await buildSnapshotJson(
        mode: AssistantMode.invest,
        userMessage: trimmed,
        summary: summary,
        quoteRepository: ref.read(quoteRepositoryProvider),
        riskProfile: riskProfile,
      );
    } else {
      snapshotJson = await buildSnapshotJson(mode: _currentMode);
    }

    final snapshot = jsonDecode(snapshotJson) as Map<String, dynamic>;
    final validation = SnapshotGroundingValidator.validate(
      mode: _currentMode,
      snapshot: snapshot,
    );

    if (_currentMode == AssistantMode.portfolio &&
        validation == SnapshotValidation.noPortfolioData) {
      if (mounted) {
        setState(() {
          _error = 'portfolio_qa_no_positions'.tr();
        });
      }
      return;
    }

    if (_currentMode == AssistantMode.explore &&
        validation == SnapshotValidation.exploreFetchFailed) {
      final tickers = snapshot['explore_tickers'] as Map?;
      final errorKey =
          tickers == null || tickers.isEmpty
              ? 'assistant_explore_no_ticker'
              : 'assistant_explore_fetch_failed';
      if (mounted) {
        setState(() {
          _error = errorKey.tr();
        });
      }
      return;
    }

    if (_currentMode == AssistantMode.invest &&
        validation == SnapshotValidation.exploreFetchFailed) {
      if (mounted) {
        setState(() {
          _error = 'assistant_invest_fetch_failed'.tr();
        });
      }
      return;
    }

    final surfaceId =
        GenUiSurfaceIds.assistantTurn(_currentMode, _turnCounter++);
    _lastMessage = trimmed;

    await _sendGuard.run(() async {
      if (mounted) {
        setState(() {
          _error = null;
          _isWaiting = true;
          _messages.add(
            PortfolioQaMessage(role: PortfolioQaRole.user, content: trimmed),
          );
          _messages.add(
            PortfolioQaMessage(
              role: PortfolioQaRole.assistant,
              surfaceId: surfaceId,
              isStreaming: true,
            ),
          );
        });
        _textController.clear();
        _scrollToBottom();
      }

      try {
        await GenUiRequestTracker.sendAndWait(
          conversation: _service!.conversation,
          targetSurfaceId: surfaceId,
          send:
              () => _service!.sendWithSnapshot(
                userQuestion: trimmed,
                portfolioSnapshotJson: snapshotJson,
                surfaceId: surfaceId,
              ),
        );

        if (mounted) {
          _markTurnReady(surfaceId);
          setState(() => _isWaiting = false);
          _scrollToBottom();
        }
      } on TimeoutException catch (e) {
        if (mounted) {
          setState(() {
            _error = e.message ?? 'GPT tardó demasiado en responder.';
            _isWaiting = false;
            _removeStreamingPlaceholder();
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = genUiErrorMessage(e);
            _isWaiting = false;
            _removeStreamingPlaceholder();
          });
        }
      }
    });
  }

  void _removeStreamingPlaceholder() {
    if (_messages.isNotEmpty && _messages.last.isStreaming) {
      _messages.removeLast();
    }
  }

  @override
  Widget buildView(BuildContext context) {
    final service = _service;

    return Scaffold(
      backgroundColor: PortfolioColors.background,
      appBar: AppBar(
        backgroundColor: PortfolioColors.background,
        elevation: 0,
        title: Text(
          'portfolio_qa_title'.tr(),
          style: const TextStyle(
            color: PortfolioColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: PortfolioColors.textPrimary),
      ),
      body: Column(
        children: [
          ModeChipBar(
            selectedMode: _currentMode,
            onModeSelected: (mode) {
              if (mode == _currentMode) return;
              setState(() {
                _currentMode = mode;
                _updateWelcomeIfOnlyMessage();
              });
              unawaited(_rebuildCatalogForMode());
            },
          ),
          const PortfolioQaDisclaimerBanner(),
          if (_modeSuggestion case final suggestion?)
            ModeSwitchSuggestion(
              reasonKey: suggestion.reasonKey,
              suggestedMode: suggestion.suggestedMode,
              onSwitch: _switchModeAndSend,
              onDismiss: _dismissSuggestionAndSend,
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Material(
                color: PortfolioColors.surfaceCard,
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  dense: true,
                  title: Text(
                    _error!,
                    style: const TextStyle(
                      color: PortfolioColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed:
                        _isWaiting || _lastMessage.isEmpty
                            ? null
                            : () {
                              setState(() => _error = null);
                              _sendMessage(_lastMessage);
                            },
                    child: Text('retry'.tr()),
                  ),
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  children: [
                    if (service != null)
                      ..._messages.map(
                        (m) => _buildMessageTile(service, m),
                      )
                    else
                      ..._messages.map(
                        (m) => PortfolioQaChatBubble(message: m),
                      ),
                    if (_messages.length <= 1) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            _chipKeys
                                .map(
                                  (key) => ActionChip(
                                    label: Text(key.tr()),
                                    onPressed:
                                        _isWaiting || service == null
                                            ? null
                                            : () => _submitMessage(key.tr()),
                                  ),
                                )
                                .toList(),
                      ),
                    ],
                  ],
                ),
                if (service == null)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      style: const TextStyle(
                        color: PortfolioColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'portfolio_qa_input_hint'.tr(),
                        filled: true,
                        fillColor: PortfolioColors.surfaceCard,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: _isWaiting ? null : _submitMessage,
                      enabled: !_isWaiting && service != null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed:
                        _isWaiting || service == null
                            ? null
                            : () => _submitMessage(_textController.text),
                    icon: const Icon(Icons.send),
                    color: PortfolioColors.accentBlue,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageTile(
    AssistantOpenAiService service,
    PortfolioQaMessage message,
  ) {
    final key = ValueKey(
      message.surfaceId ?? '${message.role.name}_${message.content.hashCode}',
    );

    if (message.surfaceId != null && !message.isStreaming) {
      return PortfolioQaAssistantSurface(
        key: key,
        surfaceId: message.surfaceId!,
        surfaceContext: service.controller.contextFor(message.surfaceId!),
      );
    }

    return PortfolioQaChatBubble(key: key, message: message);
  }
}
