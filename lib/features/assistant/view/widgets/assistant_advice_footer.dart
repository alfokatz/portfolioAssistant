import 'package:easy_localization/easy_localization.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/source_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/investor_profile/nav/investor_profile_router.dart';
import 'package:portfolio_assistant/features/porty_memory/nav/porty_memory_router.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Avisos fijos debajo de una respuesta de Invertir/Planificar: el aviso
/// de perfil de inversor (si falta o venció) y el disclaimer de sugerencia
/// informativa. Los pone la app, no el modelo — ver
/// `PortfolioQaMessage.showsAdviceDisclaimer`/`profileNudge`.
class AssistantAdviceFooter extends StatelessWidget {
  const AssistantAdviceFooter({super.key, required this.message});

  final PortfolioQaMessage message;

  static bool hasContent(PortfolioQaMessage message) =>
      message.showsAdviceDisclaimer ||
      message.profileNudge != null ||
      message.rememberedFacts.isNotEmpty ||
      message.sources.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final nudge = message.profileNudge;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.sp12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message.sources.isNotEmpty)
            QaSourceList(sources: message.sources),
          if (message.rememberedFacts.isNotEmpty)
            _MemoryNote(facts: message.rememberedFacts),
          if (nudge != null) _ProfileNudge(nudge: nudge),
          if (message.showsAdviceDisclaimer) const _AdviceDisclaimer(),
        ],
      ),
    );
  }
}

/// Misma pieza visual que un `QaTipBanner` informativo (shell destacado de
/// Porty), más un link que abre directo Ajustes → Perfil de inversor. El
/// texto nombra la fila con las mismas claves que usa Ajustes, así nunca
/// se desincroniza del label real.
class _ProfileNudge extends StatelessWidget {
  const _ProfileNudge({required this.nudge});

  final InvestorProfileNudge nudge;

  @override
  Widget build(BuildContext context) {
    final isStale = nudge == InvestorProfileNudge.stale;
    final args = ['settings_title'.tr(), 'settings_investor_profile'.tr()];
    final text =
        isStale
            ? 'assistant_profile_nudge_stale'.tr(args: args)
            : 'assistant_profile_nudge_missing'.tr(args: args);
    final action =
        isStale
            ? 'assistant_profile_nudge_action_stale'.tr()
            : 'assistant_profile_nudge_action_missing'.tr();

    final colors = context.customColors;
    return QaCardShell(
      highlighted: true,
      margin: const EdgeInsets.only(top: AppDimens.sp6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_outline,
            size: 16,
            color: colors.accentBlue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    color: colors.textPrimary.withValues(alpha: 0.9),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                TextButton(
                  onPressed:
                      () => context.pushNamed(InvestorProfileRouter.routeName),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.accentDim,
                    minimumSize: const Size(0, AppDimens.touchTarget),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.padded,
                    alignment: Alignment.centerLeft,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        action,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right_rounded, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Porty anotó: …" — lo que guardó en su memoria en este turno, tocable
/// para ver o borrar todo lo que sabe (Ajustes → Lo que Porty sabe de vos).
class _MemoryNote extends StatelessWidget {
  const _MemoryNote({required this.facts});

  final List<String> facts;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: colors.textSecondary,
      height: 1.4,
    );
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        onTap: () => context.pushNamed(PortyMemoryRouter.routeName),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDimens.sp4),
            child: Row(
              children: [
                Icon(
                  Icons.bookmark_add_outlined,
                  size: 14,
                  color: colors.accentBlue,
                ),
                const SizedBox(width: AppDimens.sp6),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'assistant_memory_noted'.tr(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: ' ${facts.join(' · ')}'),
                      ],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
                const SizedBox(width: AppDimens.sp4),
                Text(
                  'assistant_memory_see'.tr(),
                  style: style?.copyWith(
                    color: colors.accentDim,
                    fontWeight: FontWeight.w600,
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

class _AdviceDisclaimer extends StatelessWidget {
  const _AdviceDisclaimer();

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.sp8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline_rounded,
              size: 12,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: AppDimens.sp4),
          Expanded(
            child: Text(
              'assistant_advice_disclaimer'.tr(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
