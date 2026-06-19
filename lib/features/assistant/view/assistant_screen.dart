import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/providers/assistant_provider.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/ai_usage_indicator.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/mode_chip_bar.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/mode_switch_suggestion.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/portfolio_qa_assistant_surface.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/portfolio_qa_chat_bubble.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/portfolio_qa_disclaimer_banner.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

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
  late final AssistantArgs _args;

  @override
  void initState() {
    _args = AssistantArgs(
      initialMode: widget.initialMode,
      initialQuestion: widget.initialQuestion,
    );
    super.initState();
    runAfterPostFrameCallback(
      () => ref.read(assistantProvider(_args).notifier).bootstrap(),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
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

  Future<void> _submitMessage(AssistantProvider notifier, String text) async {
    if (text.trim().isEmpty) return;
    await notifier.submitMessage(text);
    _textController.clear();
    _scrollToBottom();
  }

  bool _isInputBlocked(AssistantProvider notifier, AssistantState state) =>
      state.isWaiting || notifier.isSendInFlight || notifier.service == null;

  @override
  Widget buildView(BuildContext context) {
    final state = ref.watch(assistantProvider(_args));
    final notifier = ref.read(assistantProvider(_args).notifier);
    final service = notifier.service;
    final subscription = ref.watch(subscriptionProvider);

    ref.listen(assistantProvider(_args), (previous, next) {
      if (previous?.messages.length != next.messages.length ||
          previous?.isWaiting != next.isWaiting) {
        _scrollToBottom();
      }

      final reason = next.paywallReason;
      if (reason != null && reason != previous?.paywallReason) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          SubscriptionPaywallSheet.show(
            context,
            ref,
            reason: reason,
            onUpgraded: () => ref
                .read(subscriptionProvider.notifier)
                .refresh(),
          ).whenComplete(notifier.clearPaywall);
        });
      }
    });

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
            selectedMode: state.currentMode,
            onModeSelected: notifier.selectMode,
            tier: subscription.tier,
            onLockedModeTap: (_) {
              SubscriptionPaywallSheet.show(
                context,
                ref,
                reason: PaywallReason.modeLocked,
              );
            },
          ),
          const AiUsageIndicator(),
          const PortfolioQaDisclaimerBanner(),
          if (state.modeSuggestion case final suggestion?)
            ModeSwitchSuggestion(
              reasonKey: suggestion.reasonKey,
              suggestedMode: suggestion.suggestedMode,
              onSwitch: notifier.switchModeAndSend,
              onDismiss: notifier.dismissModeSuggestion,
            ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Material(
                color: PortfolioColors.surfaceCard,
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  dense: true,
                  title: Text(
                    state.error!,
                    style: const TextStyle(
                      color: PortfolioColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: state.isWaiting || state.lastMessage.isEmpty
                        ? null
                        : notifier.clearErrorAndRetry,
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
                      ...state.messages.map(
                        (m) => _buildMessageTile(service, m),
                      )
                    else
                      ...state.messages.map(
                        (m) => PortfolioQaChatBubble(message: m),
                      ),
                    if (state.messages.length <= 1) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: notifier.chipKeys
                            .map(
                              (key) => ActionChip(
                                label: Text(key.tr()),
                                onPressed: _isInputBlocked(notifier, state)
                                    ? null
                                    : () => _submitMessage(notifier, key.tr()),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
                if (!state.isServiceReady)
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
                      maxLines: 1,
                      textInputAction: TextInputAction.send,
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
                      onSubmitted: _isInputBlocked(notifier, state)
                          ? null
                          : (text) => _submitMessage(notifier, text),
                      onEditingComplete: _isInputBlocked(notifier, state)
                          ? null
                          : () => _submitMessage(
                                notifier,
                                _textController.text,
                              ),
                      enabled: !_isInputBlocked(notifier, state),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isInputBlocked(notifier, state)
                        ? null
                        : () => _submitMessage(notifier, _textController.text),
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
