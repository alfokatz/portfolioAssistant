import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Línea de cuota baja bajo una respuesta ("Te quedan 5 consultas este mes.
/// Con Premium tenés 500."): texto secundario como [AssistantQuietNotice],
/// sin card ni color de alerta, con el link "Ver planes". La pone la app,
/// no el modelo: [remaining] sale de la suscripción y el plan y su cuota,
/// de `PlanMatrix`. Sin plan siguiente (Gold) no se dibuja.
class AssistantQuotaNudge extends StatelessWidget {
  const AssistantQuotaNudge({
    super.key,
    required this.remaining,
    required this.tier,
    required this.onSeePlans,
  });

  final int remaining;

  /// El plan actual: la línea ofrece el siguiente.
  final SubscriptionTier tier;
  final VoidCallback onSeePlans;

  @override
  Widget build(BuildContext context) {
    final next = PlanMatrix.nextTier(tier);
    if (next == null) return const SizedBox.shrink();
    final colors = context.customColors;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: colors.textSecondary,
      height: 1.4,
    );
    final text = 'assistant_quota_nudge'.tr(
      namedArgs: {
        'remaining': '$remaining',
        'plan': _planTitle(next),
        'count': '${PlanMatrix.of(next).monthlyQueries}',
      },
    );
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.sp6),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: style),
            TextButton(
              onPressed: onSeePlans,
              style: TextButton.styleFrom(
                foregroundColor: colors.accentDim,
                minimumSize: const Size(0, AppDimens.touchTarget),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.padded,
                alignment: Alignment.centerLeft,
              ),
              child: Text(
                'assistant_quota_nudge_cta'.tr(),
                style: style?.copyWith(
                  color: colors.accentDim,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _planTitle(SubscriptionTier tier) => switch (tier) {
    SubscriptionTier.premium => 'paywall_premium_title'.tr(),
    SubscriptionTier.gold => 'paywall_gold_title'.tr(),
    SubscriptionTier.free => '',
  };
}
