import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/flows/onboarding/ui/widgets/onboarding_mockup_widgets.dart';

/// Los avisos de Porty como llegan al teléfono: una alerta de precio que se
/// cumplió, el informe de la semana y los resultados de una empresa propia.
class OnboardingNotificationsPreview extends StatelessWidget {
  const OnboardingNotificationsPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'onboarding_alerts_push_alert_time'.tr(),
        'onboarding_alerts_push_alert_title'.tr(
          namedArgs: {'price': QaFormat.money(150)},
        ),
        'onboarding_alerts_push_alert_body'.tr(
          namedArgs: {'price': QaFormat.price(148.2)},
        ),
      ),
      (
        'onboarding_alerts_push_weekly_time'.tr(),
        'onboarding_alerts_push_weekly_title'.tr(),
        'onboarding_alerts_push_weekly_body'.tr(
          namedArgs: {'pct': QaFormat.pct(2.4)},
        ),
      ),
      (
        'onboarding_alerts_push_earnings_time'.tr(),
        'onboarding_alerts_push_earnings_title'.tr(),
        'onboarding_alerts_push_earnings_body'.tr(
          namedArgs: {'amount': QaFormat.price(1.62)},
        ),
      ),
    ];

    return Column(
      children: [
        for (final (i, (time, title, body)) in items.indexed) ...[
          if (i > 0) const SizedBox(height: AppDimens.sp8),
          _Notification(time: time, title: title, body: body),
        ],
      ],
    );
  }
}

class _Notification extends StatelessWidget {
  const _Notification({
    required this.time,
    required this.title,
    required this.body,
  });

  final String time;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    return MergeSemantics(
      child: OnboardingMockCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExcludeSemantics(child: PortyAvatar(size: 30)),
            const SizedBox(width: AppDimens.sp12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppDimens.sp8),
                      // El título manda; la hora, a la derecha y acotada.
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 72),
                        child: ExcludeSemantics(
                          child: Text(
                            time,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.labelSmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
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
          ],
        ),
      ),
    );
  }
}
