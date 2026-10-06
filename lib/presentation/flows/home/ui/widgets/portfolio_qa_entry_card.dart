import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/porty_question_pill.dart';

/// Entrada a Porty desde Insights: su avatar, qué le podés preguntar y
/// algunas preguntas listas que abren el chat ya enviadas (las mismas
/// pastillas que "Seguí con Porty" del informe semanal).
class PortfolioQaEntryCard extends StatelessWidget {
  const PortfolioQaEntryCard({
    super.key,
    required this.onOpen,
    required this.onAsk,
    this.suggestions = const [],
  });

  /// Abre el chat vacío.
  final VoidCallback onOpen;

  /// Abre el chat con [suggestions] ya preguntada.
  final ValueChanged<String> onAsk;

  /// Preguntas listas (salen de los datos de la cartera, ver la Home).
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sp16,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          border: Border.all(color: colors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                child: InkWell(
                  onTap: () {
                    PortyHapticsService.maybeOf(context)?.selectionTap();
                    onOpen();
                  },
                  borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppDimens.touchTarget,
                    ),
                    child: Row(
                      children: [
                        const ExcludeSemantics(child: PortyAvatar(size: 40)),
                        const SizedBox(width: AppDimens.sp12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'home_porty_entry_title'.tr(),
                                style: tt.titleMedium?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'home_porty_entry_subtitle'.tr(),
                                style: tt.bodySmall?.copyWith(
                                  color: colors.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppDimens.sp8),
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
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: AppDimens.sp12),
                Wrap(
                  spacing: AppDimens.sp8,
                  runSpacing: AppDimens.sp8,
                  children: [
                    for (final q in suggestions)
                      PortyQuestionPill(question: q, onTap: () => onAsk(q)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
