import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/models/porty_screen_context.dart';
import 'package:portfolio_assistant/features/assistant/providers/assistant_provider.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/assistant/view/assistant_screen.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// El chat de Porty como hoja sobre la pantalla en la que está el usuario:
/// pregunta, lee la respuesta y, al bajar la hoja, sigue donde estaba. Es la
/// misma conversación que la pestaña de Porty ([AssistantArgs.session]).
abstract final class PortyChatSheet {
  /// Qué parte de la pantalla ocupa (más con el teclado abierto, para que
  /// la respuesta no quede en una franja).
  static const heightFactor = 0.75;
  static const heightFactorWithKeyboard = 0.92;

  /// Abre la hoja. Con [question], la pregunta sale apenas abre; sin ella,
  /// la hoja ofrece las preguntas de [screen].
  static Future<void> show(
    BuildContext context, {
    PortyScreenContext? screen,
    String? question,
  }) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final trimmed = question?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      container
          .read(assistantProvider(AssistantArgs.session).notifier)
          .askFromOutside(trimmed, screen: screen);
    }
    final open = container.read(portyChatSheetOpenProvider.notifier);
    open.state = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        clipBehavior: Clip.antiAlias,
        builder:
            (sheetContext) => _SheetFrame(
              child: AssistantScreen(
                presentation: AssistantPresentation.sheet,
                screen: screen,
              ),
            ),
      );
    } finally {
      open.state = false;
    }
  }
}

/// La hoja al [PortyChatSheet.heightFactor] del alto disponible (sin el
/// área segura de arriba).
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return LayoutBuilder(
      builder:
          (context, constraints) => AnimatedContainer(
            duration:
                MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height:
                constraints.maxHeight *
                (keyboard
                    ? PortyChatSheet.heightFactorWithKeyboard
                    : PortyChatSheet.heightFactor),
            child: child,
          ),
    );
  }
}

/// El acceso a Porty en la barra de arriba de una pantalla: Porty pensando
/// con un globito de pregunta. Abre [PortyChatSheet] con lo que se está
/// mirando.
class PortyAskButton extends StatelessWidget {
  const PortyAskButton({super.key, required this.screen});

  final PortyScreenContext screen;

  static const _avatar = 30.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return IconButton(
      tooltip: 'porty_ask_tooltip'.tr(),
      onPressed: () {
        PortyHapticsService.maybeOf(context)?.selectionTap();
        unawaited(PortyChatSheet.show(context, screen: screen));
      },
      icon: SizedBox.square(
        dimension: _avatar + 4,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned(
              left: 0,
              bottom: 0,
              child: ExcludeSemantics(
                child: PortyAvatar(
                  size: _avatar,
                  state: PortyAvatarState.thinking,
                ),
              ),
            ),
            // El globito de pregunta: "preguntale".
            Positioned(
              right: -2,
              top: -3,
              child: Container(
                width: 15,
                height: 15,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.surfaceCard,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.border),
                ),
                child: Text(
                  '?',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: colors.accentBlue,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
