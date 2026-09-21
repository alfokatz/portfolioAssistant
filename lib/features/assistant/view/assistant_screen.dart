import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/navigation/app_tab_navigation.dart';
import 'package:portfolio_assistant/features/assistant/models/assistant_mode.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/assistant/providers/assistant_provider.dart';
import 'package:portfolio_assistant/features/assistant/services/assistant_openai_service.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/ai_usage_indicator.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_suggestion_chip.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_thinking_orb.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/mode_chip_bar.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/mode_switch_suggestion.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/portfolio_qa_assistant_surface.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/portfolio_qa_chat_bubble.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/portfolio_qa_disclaimer_banner.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/ui/subscription_paywall_sheet.dart';
import 'package:portfolio_assistant/presentation/base/core/base_stateful_widget.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/app_bottom_nav_bar.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/fade_slide_in.dart';

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
    // Se limpia antes de esperar la respuesta: dejar el texto visible
    // durante todo el round-trip invitaba a un segundo tap sobre el mismo
    // mensaje mientras el turno anterior seguía en curso.
    _textController.clear();
    await notifier.submitMessage(text);
    _scrollToBottom();
  }

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
            onUpgraded: () => ref.read(subscriptionProvider.notifier).refresh(),
          ).whenComplete(notifier.clearPaywall);
        });
      }
    });

    return Scaffold(
      bottomNavigationBar: AppBottomNavBar(
        current: AppNavDestination.assistant,
        onSelect: (destination) => goToAppTab(context, destination),
      ),
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pageHorizontal,
                AppDimens.sp12,
                AppDimens.pageHorizontal,
                AppDimens.sp4,
              ),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: PortfolioColors.surfaceElevated,
                      boxShadow: [
                        BoxShadow(
                          color: PortfolioColors.accentBlue.withValues(
                            alpha: 0.18,
                          ),
                          blurRadius: AppDimens.glowBlurSm,
                        ),
                        BoxShadow(
                          color: PortfolioColors.accentWarm.withValues(
                            alpha: 0.16,
                          ),
                          blurRadius: AppDimens.glowBlurSm,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 13,
                      color: PortfolioColors.accentBlue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'portfolio_qa_title'.tr(),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: PortfolioColors.textSecondary,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
              onDismiss: notifier.dismissSuggestionAndSend,
            ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.pageHorizontal,
                vertical: AppDimens.sp4,
              ),
              child: Material(
                color: PortfolioColors.surfaceCard,
                borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                child: ListTile(
                  dense: true,
                  title: Text(
                    state.error!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: PortfolioColors.textSecondary,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed:
                        state.isWaiting || state.lastMessage.isEmpty
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
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.pageHorizontal,
                    AppDimens.sp8,
                    AppDimens.pageHorizontal,
                    AppDimens.sp8,
                  ),
                  children: [
                    if (service != null)
                      ...state.messages.map(
                        (m) => _buildMessageTile(notifier, service, m),
                      )
                    else
                      ...state.messages.map(
                        (m) => PortfolioQaChatBubble(message: m),
                      ),
                    if (state.messages.length <= 1) ...[
                      const SizedBox(height: 4),
                      FadeSlideIn(
                        child: Text(
                          'portfolio_qa_chip_intro'.tr(),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: PortfolioColors.textSecondary),
                        ),
                      ),
                      const SizedBox(height: AppDimens.sp12),
                      for (final (i, key) in notifier.chipKeys.indexed) ...[
                        if (i > 0) const SizedBox(height: 8),
                        FadeSlideIn(
                          delay: Duration(milliseconds: 60 * (i + 1)),
                          child: AssistantSuggestionChip(
                            label: key.tr(),
                            onTap:
                                state.isWaiting || service == null
                                    ? null
                                    : () => _submitMessage(notifier, key.tr()),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
                if (!state.isServiceReady)
                  const Center(
                    child: AssistantThinkingOrb(size: AppDimens.sp32),
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.pageHorizontal,
                AppDimens.sp8,
                AppDimens.pageHorizontal,
                AppDimens.sp12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'portfolio_qa_input_hint'.tr(),
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: PortfolioColors.textPrimary,
                      ),
                      maxLines: 4,
                      minLines: 1,
                      onSubmitted:
                          state.isWaiting
                              ? null
                              : (text) => _submitMessage(notifier, text),
                      enabled: !state.isWaiting && service != null,
                    ),
                  ),
                  const SizedBox(width: AppDimens.sp8),
                  _SendButton(
                    onTap:
                        state.isWaiting || service == null
                            ? null
                            : () =>
                                _submitMessage(notifier, _textController.text),
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
    AssistantProvider notifier,
    AssistantOpenAiService fallbackService,
    PortfolioQaMessage message,
  ) {
    // Key estable: identifica la fila para el ListView a través de todo su
    // ciclo de vida (orbe → respuesta), así el AnimatedSwitcher de abajo
    // conserva su estado entre rebuilds en vez de perder la animación.
    final stableKey = ValueKey(
      message.surfaceId ?? '${message.role.name}_${message.content.hashCode}',
    );

    late final Key contentKey;
    late final Widget content;

    if (message.surfaceId != null && message.isStreaming) {
      // Sin chrome de burbuja: el orbe flota suelto en el lugar donde va a
      // aparecer la respuesta, en vez de quedar encerrado en un contenedor.
      // Sin deriva vertical: acá el orbe marca un punto exacto — dónde va
      // a aparecer la respuesta — y alejarse de ese punto contradice esa
      // promesa espacial.
      contentKey = const ValueKey('thinking');
      content = Padding(
        padding: const EdgeInsets.only(bottom: AppDimens.sp12),
        child: const Align(
          alignment: Alignment.centerLeft,
          child: AssistantThinkingOrb(size: AppDimens.iconLg),
        ),
      );
    } else if (message.surfaceId != null) {
      contentKey = const ValueKey('surface');
      final surfaceService =
          message.engineMode == null
              ? fallbackService
              : (notifier.serviceFor(message.engineMode!) ?? fallbackService);
      content = PortfolioQaAssistantSurface(
        surfaceId: message.surfaceId!,
        surfaceContext: surfaceService.controller.contextFor(
          message.surfaceId!,
        ),
      );
    } else {
      contentKey = const ValueKey('bubble');
      content = PortfolioQaChatBubble(message: message);
    }

    // El orbe no tenía salida propia: al llegar la respuesta, desaparecía de
    // golpe reemplazado por la card. El crossfade acá hace que se desvanezca
    // mientras la card entra, en vez de un swap instantáneo y desconectado.
    return AnimatedSwitcher(
      key: stableKey,
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder:
          (child, animation) =>
              FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(key: contentKey, child: content),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        boxShadow:
            enabled
                ? [
                  BoxShadow(
                    color: PortfolioColors.accentBlue.withValues(alpha: 0.30),
                    blurRadius: AppDimens.glowBlurSm,
                  ),
                  BoxShadow(
                    color: PortfolioColors.accentWarm.withValues(alpha: 0.22),
                    blurRadius: AppDimens.glowBlurMd,
                  ),
                ]
                : null,
      ),
      child: Material(
        color:
            enabled
                ? PortfolioColors.accentBlue
                : PortfolioColors.accentBlue.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.arrow_upward_rounded,
              color: PortfolioColors.textPrimary,
              size: AppDimens.iconMd,
            ),
          ),
        ),
      ),
    );
  }
}
