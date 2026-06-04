import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_error_message.dart';
import 'package:portfolio_assistant/features/genui_core/utils/gen_ui_send_guard.dart';
import 'package:portfolio_assistant/features/portfolio_qa/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/portfolio_qa/services/portfolio_qa_service.dart';
import 'package:portfolio_assistant/features/portfolio_qa/utils/portfolio_context_builder.dart';
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
  late final PortfolioQaService _service;

  final List<PortfolioQaMessage> _messages = [];
  String? _error;
  bool _isWaiting = false;
  bool _bootstrapped = false;

  static const _chipKeys = [
    'portfolio_qa_chip_today',
    'portfolio_qa_chip_risk',
    'portfolio_qa_chip_pnl',
  ];

  @override
  void initState() {
    super.initState();
    _service = PortfolioQaService();
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

    final question = widget.initialQuestion?.trim();
    if (question != null && question.isNotEmpty) {
      await _sendMessage(question);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _service.dispose();
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
    if (trimmed.isEmpty || _sendGuard.isInFlight) return;

    final summary = ref.read(homeProvider).summary;
    if (summary == null || summary.valuations.isEmpty) {
      if (mounted) {
        setState(() {
          _error = 'portfolio_qa_no_positions'.tr();
        });
      }
      return;
    }

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
              content: '',
              isStreaming: true,
            ),
          );
        });
        _textController.clear();
        _scrollToBottom();
      }

      final snapshotJson = PortfolioContextBuilder.buildJson(summary);

      try {
        var assistantIndex = _messages.length - 1;
        await _service.sendMessage(
          userQuestion: trimmed,
          portfolioSnapshotJson: snapshotJson,
          onChunk: (chunk) {
            if (!mounted) return;
            setState(() {
              final current = _messages[assistantIndex];
              _messages[assistantIndex] = current.copyWith(
                content: current.content + chunk,
              );
            });
            _scrollToBottom();
          },
        );

        if (mounted) {
          setState(() {
            final current = _messages[assistantIndex];
            _messages[assistantIndex] = current.copyWith(isStreaming: false);
            _isWaiting = false;
          });
          _scrollToBottom();
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isWaiting = false;
            _error = genUiErrorMessage(e);
            if (_messages.isNotEmpty &&
                _messages.last.isStreaming &&
                _messages.last.content.isEmpty) {
              _messages.removeLast();
            }
          });
        }
      }
    });
  }

  @override
  Widget buildView(BuildContext context) {
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
                    onPressed: _isWaiting
                        ? null
                        : () => setState(() => _error = null),
                    child: Text('retry'.tr()),
                  ),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              children: [
                ..._messages.map(
                  (m) => PortfolioQaChatBubble(message: m),
                ),
                if (_messages.length <= 1) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _chipKeys
                        .map(
                          (key) => ActionChip(
                            label: Text(key.tr()),
                            onPressed: _isWaiting ? null : () => _sendMessage(key.tr()),
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
                      style: const TextStyle(color: PortfolioColors.textPrimary),
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
                      enabled: !_isWaiting,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isWaiting
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
}
