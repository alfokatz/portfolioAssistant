import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Input del chat de Porty (token `input-field-chat` en DESIGN.md).
///
/// Fork deliberado del `inputDecorationTheme` global: los inputs de
/// formularios (add/close position) siguen con radius md y fill Elevated
/// Mist; acá el campo es una píldora sobre Pure Surface para que se lea
/// despegado del Warm Canvas + halo sin recurrir a sombra en reposo. En foco
/// suma un glow terracota tenue alrededor del borde — feedback de
/// interacción, no elevación ambiental.
class AssistantComposerField extends StatefulWidget {
  const AssistantComposerField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onSubmitted,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  /// Alto de una sola línea; el send button usa el mismo diámetro.
  static const height = AppDimens.composerHeight;

  @override
  State<AssistantComposerField> createState() => _AssistantComposerFieldState();
}

class _AssistantComposerFieldState extends State<AssistantComposerField> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() => setState(() {});

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final focused = _focusNode.hasFocus;
    const radius = BorderRadius.all(Radius.circular(AppDimens.radiusPill));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(
        minHeight: AssistantComposerField.height,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: radius,
        border: Border.all(
          color: focused ? colors.accentBlue : colors.border,
          width: focused ? 1.5 : 1,
        ),
        boxShadow: [
          // Siempre presente (alpha 0 en reposo) para que AnimatedContainer
          // interpole el glow en vez de hacerlo aparecer de golpe.
          BoxShadow(
            color: colors.accentBlue.withValues(alpha: focused ? 0.16 : 0),
            blurRadius: AppDimens.glowBlurSm,
          ),
        ],
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.sp20),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        onSubmitted: widget.onSubmitted,
        maxLines: 4,
        minLines: 1,
        cursorColor: colors.accentBlue,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary.withValues(alpha: 0.6),
          ),
          isCollapsed: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }
}

/// Send del chat (`button-send-chat`): círculo del mismo diámetro que
/// [AssistantComposerField], alineado a su base cuando el campo crece.
class AssistantSendButton extends StatelessWidget {
  const AssistantSendButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
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
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: const SizedBox(
            width: AssistantComposerField.height,
            height: AssistantComposerField.height,
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

/// Dictado del chat, al lado del send: mismo diámetro, pero calmo (borde
/// sobre Pure Surface) para que el send siga siendo la acción principal.
/// Escuchando, se tiñe de terracota con un halo que respira y muestra
/// "stop".
class AssistantMicButton extends StatefulWidget {
  const AssistantMicButton({
    super.key,
    required this.listening,
    this.onTap,
  });

  final bool listening;
  final VoidCallback? onTap;

  @override
  State<AssistantMicButton> createState() => _AssistantMicButtonState();
}

class _AssistantMicButtonState extends State<AssistantMicButton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(AssistantMicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listening != widget.listening) _sync();
  }

  void _sync() {
    if (widget.listening) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final enabled = widget.onTap != null;
    final listening = widget.listening;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label:
          listening
              ? 'assistant_mic_stop'.tr()
              : 'assistant_mic_start'.tr(),
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final glow = reduceMotion ? 0.5 : _pulse.value;
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow:
                  listening
                      ? [
                        BoxShadow(
                          color: PortfolioColors.accentBlue.withValues(
                            alpha: 0.18 + 0.22 * glow,
                          ),
                          blurRadius: AppDimens.glowBlurSm + 8 * glow,
                          spreadRadius: 2 * glow,
                        ),
                      ]
                      : null,
            ),
            child: child,
          );
        },
        child: Material(
          color:
              listening
                  ? PortfolioColors.accentBlue
                  : colors.surfaceCard.withValues(alpha: enabled ? 1 : 0.6),
          shape: CircleBorder(
            side:
                listening
                    ? BorderSide.none
                    : BorderSide(color: colors.border),
          ),
          child: InkWell(
            onTap: widget.onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: AssistantComposerField.height,
              height: AssistantComposerField.height,
              child: Icon(
                listening ? Icons.stop_rounded : Icons.mic_none_rounded,
                color:
                    listening
                        ? PortfolioColors.textPrimary
                        : colors.textSecondary.withValues(
                          alpha: enabled ? 1 : 0.5,
                        ),
                size: AppDimens.iconMd,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
