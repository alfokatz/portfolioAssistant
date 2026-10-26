import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_images.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/providers/onboarding_provider.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_entrance.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_page_header.dart';

/// El paso que importa: traer la cartera. Con ella, Porty muestra lo que ve
/// (el primer diagnóstico). Cuatro caminos, del más rápido al más lento;
/// ninguno pide pagar.
class OnboardingBringPortfolioPage extends StatelessWidget {
  const OnboardingBringPortfolioPage({
    super.key,
    required this.activePage,
    required this.onChoose,
    this.enabled = true,
  });

  static const pageIndex = 1;

  final int activePage;
  final void Function(OnboardingExit exit) onChoose;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    Widget enter(int i, Widget child) => OnboardingStaggeredEntrance(
      pageIndex: pageIndex,
      activePage: activePage,
      itemIndex: i,
      child: child,
    );
    final ways = [
      (
        exit: OnboardingExit.importFile,
        icon: Icons.description_outlined,
        title: Text('onboarding_bring_file_title'.tr()),
        label: 'onboarding_bring_file_title'.tr(),
        body: 'onboarding_bring_file_body'.tr(),
      ),
      (
        exit: OnboardingExit.connectEtoro,
        icon: Icons.link_rounded,
        title: Wrap(
          spacing: AppDimens.sp8,
          runSpacing: AppDimens.sp4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('onboarding_bring_etoro_title'.tr()),
            AppImages.etoroLogo(height: 13),
          ],
        ),
        label: 'onboarding_bring_etoro_semantics'.tr(),
        body: 'onboarding_bring_etoro_body'.tr(),
      ),
      (
        exit: OnboardingExit.writeIt,
        icon: Icons.edit_note_rounded,
        title: Text('onboarding_bring_write_title'.tr()),
        label: 'onboarding_bring_write_title'.tr(),
        body: 'onboarding_bring_write_body'.tr(),
      ),
      (
        exit: OnboardingExit.addPosition,
        icon: Icons.add_rounded,
        title: Text('onboarding_bring_manual_title'.tr()),
        label: 'onboarding_bring_manual_title'.tr(),
        body: 'onboarding_bring_manual_body'.tr(),
      ),
    ];

    return OnboardingPageEntrance(
      pageIndex: pageIndex,
      activePage: activePage,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.pageHorizontal,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppDimens.sp8),
                  enter(
                    0,
                    Center(
                      child: ExcludeSemantics(
                        child: PortyAvatar(
                          size: 64,
                          state: PortyAvatarState.answered,
                          animated: activePage == pageIndex,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp16),
                  enter(
                    1,
                    OnboardingPageHeader(
                      title: 'onboarding_bring_title'.tr(),
                      subtitle: 'onboarding_bring_subtitle'.tr(),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp24),
                  enter(
                    2,
                    Container(
                      decoration: BoxDecoration(
                        color: colors.surfaceCard,
                        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                        border: Border.all(color: colors.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final (i, w) in ways.indexed) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                thickness: 1,
                                indent: 64,
                                color: colors.border,
                              ),
                            _WayRow(
                              icon: w.icon,
                              title: w.title,
                              semanticsLabel: w.label,
                              body: w.body,
                              onTap: enabled ? () => onChoose(w.exit) : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp16),
                  enter(
                    3,
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: AppDimens.iconSm + 2,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: AppDimens.sp8),
                        Expanded(
                          child: Text(
                            'onboarding_finish_disclaimer'.tr(),
                            style: tt.bodySmall?.copyWith(
                              color: colors.textSecondary,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimens.sp16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WayRow extends StatelessWidget {
  const _WayRow({
    required this.icon,
    required this.title,
    required this.semanticsLabel,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final Widget title;
  final String semanticsLabel;
  final String body;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: semanticsLabel,
      hint: body,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.sp16,
                vertical: AppDimens.sp12,
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.chip,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 18, color: colors.onChip),
                  ),
                  const SizedBox(width: AppDimens.sp12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DefaultTextStyle.merge(
                          style: tt.titleSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          child: title,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          body,
                          style: tt.bodySmall?.copyWith(
                            color: colors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppDimens.sp8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colors.textSecondary,
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
