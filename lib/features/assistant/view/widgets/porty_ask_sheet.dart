import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/models/porty_screen_context.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_nav.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/utils/porty_screen_suggestions.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_composer_field.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/assistant_starter_suggestions.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_says.dart';

/// "Preguntale a Porty" desde cualquier pantalla: una hoja con preguntas
/// sobre lo que el usuario está mirando y un campo para escribir la suya.
/// La pregunta sale con [screen] como contexto (`screen_context` del
/// brief), así "¿por qué bajó?" se entiende sin nombrar el ticker.
class PortyAskSheet extends ConsumerStatefulWidget {
  const PortyAskSheet({super.key, required this.screen});

  final PortyScreenContext screen;

  /// Abre la hoja y, si eligió o escribió una pregunta, el chat con ella.
  static Future<void> show(
    BuildContext context, {
    required PortyScreenContext screen,
  }) async {
    final question = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PortyAskSheet(screen: screen),
    );
    if (question == null || question.trim().isEmpty || !context.mounted) {
      return;
    }
    GotoAssistant(
      initialQuestion: question,
      screen: screen,
    ).navigate(context: context);
  }

  /// La frase de Porty arriba de la hoja, según la pantalla.
  @visibleForTesting
  static String titleFor(PortyScreenContext screen) {
    final ticker = screen.ticker?.toUpperCase();
    final goal = screen.goalLabel;
    return switch (screen.screen) {
      PortyScreen.positionDetail when ticker != null => 'porty_ask_title_ticker'
          .tr(namedArgs: {'ticker': ticker}),
      PortyScreen.closedPosition when ticker != null => 'porty_ask_title_closed'
          .tr(namedArgs: {'ticker': ticker}),
      PortyScreen.goalDetail when goal != null => 'porty_ask_title_goal'.tr(
        namedArgs: {'goal': goal},
      ),
      PortyScreen.goals => 'porty_ask_title_goals'.tr(),
      PortyScreen.watchlist => 'porty_ask_title_watchlist'.tr(),
      PortyScreen.allocation => 'porty_ask_title_allocation'.tr(),
      PortyScreen.weeklyReport => 'porty_ask_title_report'.tr(),
      _ => 'porty_ask_title_generic'.tr(),
    };
  }

  @override
  ConsumerState<PortyAskSheet> createState() => _PortyAskSheetState();
}

class _PortyAskSheetState extends ConsumerState<PortyAskSheet> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _send(String question) {
    final trimmed = question.trim();
    if (trimmed.isEmpty) return;
    PortyHapticsService.maybeOf(context)?.selectionTap();
    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tier = ref.watch(subscriptionProvider).tier;
    final suggestions = [
      for (final s in PortyScreenSuggestions.forScreen(widget.screen, tier))
        (label: s.key.tr(namedArgs: s.args), icon: s.icon),
    ];
    final canSend = _controller.text.trim().isNotEmpty;

    return Padding(
      // El campo queda arriba del teclado.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          AppDimens.sp8,
          AppDimens.pageHorizontal,
          AppDimens.sp20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PortySays(
              message: Text(PortyAskSheet.titleFor(widget.screen)),
              messageKey: widget.screen.screen,
              mood: PortyAvatarState.idle,
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: AppDimens.sp20),
              Padding(
                padding: const EdgeInsets.only(
                  left: AppDimens.sp4,
                  bottom: AppDimens.sp8,
                ),
                child: Text(
                  'porty_ask_suggestions_label'.tr(),
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: colors.textSecondary),
                ),
              ),
              AssistantStarterSuggestions(
                suggestions: suggestions,
                onSelected: _send,
              ),
            ],
            const SizedBox(height: AppDimens.sp16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: AssistantComposerField(
                    controller: _controller,
                    hintText: 'porty_ask_hint'.tr(),
                    onSubmitted: _send,
                  ),
                ),
                const SizedBox(width: AppDimens.sp8),
                AssistantSendButton(
                  onTap: canSend ? () => _send(_controller.text) : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// El acceso a Porty en la barra de arriba de una pantalla: la chispa
/// terracota de Porty. Abre [PortyAskSheet] con lo que se está mirando.
class PortyAskButton extends StatelessWidget {
  const PortyAskButton({super.key, required this.screen});

  final PortyScreenContext screen;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'porty_ask_tooltip'.tr(),
      onPressed: () {
        PortyHapticsService.maybeOf(context)?.selectionTap();
        PortyAskSheet.show(context, screen: screen);
      },
      icon: PortySpark(size: 20, color: context.customColors.accentBlue),
    );
  }
}
