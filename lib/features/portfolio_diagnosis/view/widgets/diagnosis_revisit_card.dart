import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/nav/portfolio_diagnosis_router.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/providers/portfolio_diagnosis_provider.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/view/widgets/diagnosis_entry_card.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';

/// "Lo que vi en tu cartera": vuelve a abrir los hallazgos de Porty después
/// de haber visto el primer diagnóstico (antes de eso lo ofrece
/// [DiagnosisEntryCard], arriba en la Home). El diagnóstico se arma de nuevo
/// cada vez que se abre, así que siempre muestra los números de hoy.
///
/// Va arriba en la Home, debajo del total, en el lugar de
/// [DiagnosisEntryCard] (nunca están las dos). Trae su propio espacio
/// inferior; si no corresponde, no ocupa lugar.
class DiagnosisRevisitCard extends ConsumerWidget {
  const DiagnosisRevisitCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.watch(diagnosisSeenProvider);
    final hasPortfolio = ref.watch(
      homeProvider.select(
        (s) => (s.summary?.valuations.isNotEmpty ?? false) && !s.loading,
      ),
    );
    if (!seen || !hasPortfolio) return const SizedBox.shrink();

    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.pageHorizontal,
        0,
        AppDimens.pageHorizontal,
        AppDimens.sectionGap,
      ),
      child: Semantics(
        button: true,
        child: Material(
          color: colors.surfaceCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusLg),
            side: BorderSide(color: colors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              PortyHapticsService.maybeOf(context)?.selectionTap();
              context.pushNamed(PortfolioDiagnosisRouter.routeName);
            },
            child: Padding(
              padding: const EdgeInsets.all(AppDimens.cardPadding),
              child: Row(
                children: [
                  const ExcludeSemantics(
                    child: PortyAvatar(size: 40, state: PortyAvatarState.idle),
                  ),
                  const SizedBox(width: AppDimens.sp12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'diagnosis_revisit_title'.tr(),
                          style: tt.titleMedium?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'diagnosis_revisit_body'.tr(),
                          style: tt.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppDimens.sp8),
                  ExcludeSemantics(
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: AppDimens.iconMd,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
