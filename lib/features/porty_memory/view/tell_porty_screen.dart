import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/services/chat_dictation.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/porty_memory/domain/user_memory.dart';
import 'package:portfolio_assistant/features/porty_memory/providers/user_memory_provider.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/position/ui/widgets/position_primary_button.dart';

/// Una pregunta de Porty para que el usuario le cuente de sí mismo. La
/// pregunta ya define de qué se trata lo que se guarda (su categoría): el
/// usuario nunca elige una categoría a mano.
enum TellPortyPrompt {
  goal(UserMemoryCategory.goal, Icons.flag_outlined),
  finances(UserMemoryCategory.finances, Icons.savings_outlined),
  life(UserMemoryCategory.life, Icons.person_outline_rounded),
  preference(UserMemoryCategory.preference, Icons.favorite_border_rounded),
  other(UserMemoryCategory.other, Icons.chat_bubble_outline_rounded);

  const TellPortyPrompt(this.category, this.icon);
  final UserMemoryCategory category;
  final IconData icon;

  String get question => 'tell_porty_q_$name'.tr();
  String get hint => 'tell_porty_hint_$name'.tr();

  /// Ideas que se tocan para empezar (completan el campo).
  List<String> get ideas => [
    for (var i = 1; i <= 3; i++) 'tell_porty_idea_${name}_$i'.tr(),
  ];
}

/// Las preguntas de Porty como tarjetas tocables (en "Lo que Porty sabe de
/// vos"): cada una abre [TellPortyScreen].
class TellPortyPromptCards extends StatelessWidget {
  const TellPortyPromptCards({super.key, required this.onSelected});

  final ValueChanged<TellPortyPrompt> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          for (final (i, prompt) in TellPortyPrompt.values.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: AppDimens.cardPadding,
                endIndent: AppDimens.cardPadding,
                color: colors.border,
              ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(prompt),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppDimens.touchTarget + 8,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.cardPadding,
                      vertical: AppDimens.sp12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: colors.accentBlue.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            prompt.icon,
                            size: 18,
                            color: colors.accentBlue,
                          ),
                        ),
                        const SizedBox(width: AppDimens.sp12),
                        Expanded(
                          child: Text(
                            prompt.question,
                            style: tt.bodyLarge?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: AppDimens.iconMd,
                          color: colors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dictado propio de esta pantalla (no comparte estado con el del chat).
final _tellPortyDictationProvider =
    ChangeNotifierProvider.autoDispose<ChatDictation>((ref) => ChatDictation());

/// Porty pregunta ("¿Qué te gustaría comprar o lograr?") y el usuario
/// contesta escribiendo, tocando una idea o hablándole. Se guarda en la
/// memoria con la categoría de la pregunta.
class TellPortyScreen extends ConsumerStatefulWidget {
  const TellPortyScreen({super.key, required this.prompt});

  final TellPortyPrompt prompt;

  @override
  ConsumerState<TellPortyScreen> createState() => _TellPortyScreenState();
}

class _TellPortyScreenState extends ConsumerState<TellPortyScreen> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setText(String text) {
    final clipped =
        text.length > UserMemory.maxLength
            ? text.substring(0, UserMemory.maxLength)
            : text;
    _controller.value = TextEditingValue(
      text: clipped,
      selection: TextSelection.collapsed(offset: clipped.length),
    );
  }

  Future<void> _toggleMic() async {
    final dictation = ref.read(_tellPortyDictationProvider);
    if (dictation.isListening) {
      await dictation.stop();
      return;
    }
    PortyHapticsService.maybeOf(context)?.selectionTap();
    final current = _controller.text.trim();
    final prefix = current.isEmpty ? '' : '$current ';
    final failure = await dictation.start(
      languageCode: context.locale.languageCode,
      onText: (words) {
        if (mounted) _setText('$prefix$words');
      },
    );
    if (!mounted || failure == null) return;
    ref
        .read(alertProvider.notifier)
        .showError(
          message:
              failure == DictationFailure.permission
                  ? 'assistant_mic_permission'.tr()
                  : 'assistant_mic_unavailable'.tr(),
        );
  }

  Future<void> _save() async {
    await ref.read(_tellPortyDictationProvider).stop();
    setState(() => _saving = true);
    try {
      await ref
          .read(userMemoryProvider.notifier)
          .add(_controller.text, category: widget.prompt.category);
      if (mounted) Navigator.of(context).pop(true);
    } on UserMemoryLimitReached {
      ref
          .read(alertProvider.notifier)
          .showError(message: 'porty_memory_full'.tr());
      if (mounted) setState(() => _saving = false);
    } catch (_) {
      ref
          .read(alertProvider.notifier)
          .showError(message: 'porty_memory_error'.tr());
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final prompt = widget.prompt;
    final listening = ref.watch(_tellPortyDictationProvider).isListening;
    final canSave = !_saving && _controller.text.trim().length >= 3;

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pageHorizontal,
          AppDimens.sp8,
          AppDimens.pageHorizontal,
          AppDimens.sp24,
        ),
        children: [
          // Porty pregunta: su avatar y, al lado, la pregunta.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: PortyAvatar(
                  size: 56,
                  animated: true,
                  state:
                      listening
                          ? PortyAvatarState.thinking
                          : PortyAvatarState.idle,
                ),
              ),
              const SizedBox(width: AppDimens.sp12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        prompt.question,
                        style: tt.displaySmall?.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          height: 1.25,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimens.sp6),
                    Text(
                      'tell_porty_why'.tr(),
                      style: tt.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.sp24),
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 6,
            maxLength: UserMemory.maxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: prompt.hint),
          ),
          const SizedBox(height: AppDimens.sp8),
          _MicButton(listening: listening, onTap: _saving ? null : _toggleMic),
          const SizedBox(height: AppDimens.sp24),
          Text(
            'tell_porty_ideas'.tr(),
            style: tt.labelSmall?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: AppDimens.sp8),
          Wrap(
            spacing: AppDimens.sp8,
            runSpacing: AppDimens.sp8,
            children: [
              for (final idea in prompt.ideas)
                _IdeaChip(label: idea, onTap: () => _setText(idea)),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppDimens.pageHorizontal,
            AppDimens.sp8,
            AppDimens.pageHorizontal,
            AppDimens.sp16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: PositionPrimaryButton(
            label: 'porty_memory_save'.tr(),
            loading: _saving,
            onPressed: canSave ? _save : null,
          ),
        ),
      ),
    );
  }
}

/// "Hablale a Porty": grande y obvio, para que contar sea tan fácil como
/// hablar. Escuchando se tiñe de terracota y dice cómo terminar.
class _MicButton extends StatelessWidget {
  const _MicButton({required this.listening, this.onTap});

  final bool listening;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final foreground =
        listening ? PortfolioColors.textPrimary : colors.textPrimary;
    return Semantics(
      button: true,
      child: Material(
        color: listening ? PortfolioColors.accentBlue : colors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          side:
              listening
                  ? BorderSide.none
                  : BorderSide(color: colors.accentBlue, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusPill),
          ),
          child: SizedBox(
            height: AppDimens.composerHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  listening ? Icons.stop_rounded : Icons.mic_rounded,
                  size: AppDimens.iconMd,
                  color: listening ? foreground : colors.accentBlue,
                ),
                const SizedBox(width: AppDimens.sp8),
                Flexible(
                  child: Text(
                    listening
                        ? 'tell_porty_listening'.tr()
                        : 'tell_porty_speak'.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Una idea para empezar: texto oscuro sobre fondo claro (siempre legible).
class _IdeaChip extends StatelessWidget {
  const _IdeaChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Material(
      color: colors.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        side: BorderSide(color: colors.border),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.sp12,
            vertical: AppDimens.sp8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 16, color: colors.accentBlue),
              const SizedBox(width: AppDimens.sp4),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
