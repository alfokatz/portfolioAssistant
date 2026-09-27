import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/qa_card_shell.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/features/investor_profile/nav/investor_profile_router.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Avisos fijos debajo de una respuesta de Invertir/Planificar: el aviso
/// de perfil de inversor (si falta o venció) y el disclaimer de sugerencia
/// informativa. Los pone la app, no el modelo — ver
/// `PortfolioQaMessage.showsAdviceDisclaimer`/`profileNudge`.
class AssistantAdviceFooter extends StatelessWidget {
  const AssistantAdviceFooter({super.key, required this.message});

  final PortfolioQaMessage message;

  static bool hasContent(PortfolioQaMessage message) =>
      message.showsAdviceDisclaimer || message.profileNudge != null;

  @override
  Widget build(BuildContext context) {
    final nudge = message.profileNudge;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimens.sp12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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

    return QaCardShell(
      highlighted: true,
      margin: const EdgeInsets.only(top: AppDimens.sp6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lightbulb_outline,
            size: 16,
            color: PortfolioColors.accentBlue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    color: PortfolioColors.textPrimary.withValues(alpha: 0.9),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                TextButton(
                  onPressed:
                      () => context.pushNamed(InvestorProfileRouter.routeName),
                  style: TextButton.styleFrom(
                    foregroundColor: PortfolioColors.accentBlueDim,
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

class _AdviceDisclaimer extends StatelessWidget {
  const _AdviceDisclaimer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.sp8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline_rounded,
              size: 12,
              color: PortfolioColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppDimens.sp4),
          Expanded(
            child: Text(
              'assistant_advice_disclaimer'.tr(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: PortfolioColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
