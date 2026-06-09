import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/genui_core/genui_surface_ids.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_flow_screen_helpers.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_request_tracker.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_send_guard.dart';
import 'package:portfolio_assistant/features/portfolio_qa/catalog/portfolio_qa_catalog.dart';
import 'package:portfolio_assistant/features/portfolio_qa/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/portfolio_qa/services/portfolio_qa_openai_service.dart';
import 'package:portfolio_assistant/features/portfolio_qa/utils/portfolio_context_builder.dart';
import 'package:portfolio_assistant/features/portfolio_qa/view/widgets/portfolio_qa_assistant_surface.dart';
import 'package:portfolio_assistant/features/portfolio_qa/view/widgets/portfolio_qa_chat_bubble.dart';
import 'package:portfolio_assistant/features/portfolio_qa/view/widgets/portfolio_qa_disclaimer_banner.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

class PortfolioQaScreen extends StatefulHookConsumerWidget {
  const PortfolioQaScreen({super.key, this.initialQuestion});

  final String? initialQuestion;

  @override
  ConsumerState<PortfolioQaScreen> createState() => _PortfolioQaScreenState();
}

class _PortfolioQaScreenState extends BaseStatefulWidget<PortfolioQaScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _sendGuard = GenUiSendGuard();
  final _conversationEvents = GenUiConversationSubscription();
  final _surfaceIds = <String>[];

  late final Catalog _catalog;
  PortfolioQaOpenAiService? _service;

  final List<PortfolioQaMessage> _messages = [];
  String? _error;
  bool _isWaiting = false;
  bool _bootstrapped = false;
  int _turnCounter = 0;
  String _lastMessage = '';

  static const _chipKeys = [
    'portfolio_qa_chip_today',
    'portfolio_qa_chip_risk',
    'portfolio_qa_chip_pnl',
  ];

  @override
  void initState() {
    _catalog = PortfolioQaCatalog.build();
    super.initState();
    _messages.add(
      PortfolioQaMessage(
        role: PortfolioQaRole.assistant,
        content: 'portfolio_qa_welcome'.tr(),
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
      await _sendMessage(question);
    }
  }

  Future<void> _initService() async {
    final prompt =
        PromptBuilder.custom(
          catalog: _catalog,
          allowedOperations: SurfaceOperations.createAndUpdate(
            dataModel: false,
          ),
          systemPromptFragments: _catalog.systemPromptFragments,
          technicalPossibilities: const TechnicalPossibilities(
            codeExecution: false,
            toolCall: false,
            functionCall: false,
          ),
        ).systemPromptJoined();

    _conversationEvents.cancel();
    _service?.dispose();
    _service = PortfolioQaOpenAiService(
      systemPrompt: prompt,
      catalog: _catalog,
    );

    _conversationEvents.listen(_service!.conversation, _onConversationEvent);

    if (mounted) setState(() {});
  }

  void _onConversationEvent(ConversationEvent event) {
    if (!mounted) return;
    GenUiFlowScreenHelpers.handleConversationEvent(
      event: event,
      surfaceIds: _surfaceIds,
      setError: (value) => _error = value,
      setWaiting: (value) => _isWaiting = value,
      onStateChanged: () {
        if (event
            case ConversationSurfaceAdded(:final surfaceId) ||
                ConversationComponentsUpdated(:final surfaceId)) {
          _attachSurfaceToLastAssistantTurn(surfaceId);
        }
        setState(() {});
      },
    );
  }

  void _attachSurfaceToLastAssistantTurn(String surfaceId) {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final message = _messages[i];
      if (message.role == PortfolioQaRole.assistant && message.isStreaming) {
        _messages[i] = PortfolioQaMessage(
          role: PortfolioQaRole.assistant,
          surfaceId: surfaceId,
        );
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

    final summary = ref.read(homeProvider).summary;
    if (summary == null || summary.valuations.isEmpty) {
      if (mounted) {
        setState(() {
          _error = 'portfolio_qa_no_positions'.tr();
        });
      }
      return;
    }

    final surfaceId = GenUiSurfaceIds.portfolioQaTurn(_turnCounter++);
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
            const PortfolioQaMessage(
              role: PortfolioQaRole.assistant,
              isStreaming: true,
            ),
          );
        });
        _textController.clear();
        _scrollToBottom();
      }

      final snapshotJson = PortfolioContextBuilder.buildJson(summary);

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
    if (_messages.isNotEmpty &&
        _messages.last.isStreaming &&
        !_messages.last.isGenUiSurface) {
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
          const PortfolioQaDisclaimerBanner(),
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
            child:
                service == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      children: [
                        ..._messages.map((m) => _buildMessageTile(service, m)),
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
                                            _isWaiting
                                                ? null
                                                : () => _sendMessage(key.tr()),
                                      ),
                                    )
                                    .toList(),
                          ),
                        ],
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
                      onSubmitted: _isWaiting ? null : _sendMessage,
                      enabled: !_isWaiting && service != null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed:
                        _isWaiting || service == null
                            ? null
                            : () => _sendMessage(_textController.text),
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
    PortfolioQaOpenAiService service,
    PortfolioQaMessage message,
  ) {
    if (message.isGenUiSurface && message.surfaceId != null) {
      return PortfolioQaAssistantSurface(
        surfaceId: message.surfaceId!,
        surfaceContext: service.controller.contextFor(message.surfaceId!),
      );
    }

    return PortfolioQaChatBubble(message: message);
  }
}
