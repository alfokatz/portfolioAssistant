import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/models/portfolio_qa_message.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Las dos líneas de la consulta de mercado gratis bajo una respuesta
/// (spec 2026-11-03), fuera del catálogo y con el estilo de
/// `AssistantQuotaNudge`: texto secundario, sin card ni color de alerta.
///
/// - [remaining] (turno que usó una consulta): "Consulta de mercado gratis ·
///   te quedan 2 este mes", o "era la última" con 0.
/// - [teaser] (turno respondido sin datos del ticker ajeno): el aviso de
///   Premium con el link "Ver Premium".
///
/// Los números salen del servidor y de `PlanMatrix`, nunca del modelo.
class AssistantMarketTasteNotice extends StatelessWidget {
  const AssistantMarketTasteNotice({
    super.key,
    required this.remaining,
    required this.teaser,
    required this.tier,
    required this.onSeePremium,
  });

  final int? remaining;
  final bool teaser;

  /// El plan actual: de acá sale cuántas consultas gratis tenía por mes.
  final SubscriptionTier tier;
  final VoidCallback onSeePremium;

  static bool hasContent(PortfolioQaMessage message) =>
      message.marketTasteRemaining != null || message.marketTeaser;

  @override
  Widget build(BuildContext context) {
    final left = remaining;
    if (left == null && !teaser) return const SizedBox.shrink();
    final colors = context.customColors;
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.textSecondary, height: 1.4);
    return Padding(
      padding: const EdgeInsets.only(top: AppDimens.sp6),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (left != null)
              Text(
                left > 0
                    ? 'assistant_market_taste_left'.tr(
                      namedArgs: {'remaining': '$left'},
                    )
                    : 'assistant_market_taste_last'.tr(),
                style: style,
              ),
            if (teaser) ...[
              Text(
                'assistant_market_teaser'.tr(
                  namedArgs: {
                    'count': '${PlanMatrix.of(tier).marketDataTastesPerMonth}',
                  },
                ),
                style: style,
              ),
              TextButton(
                onPressed: onSeePremium,
                style: TextButton.styleFrom(
                  foregroundColor: colors.accentDim,
                  minimumSize: const Size(0, AppDimens.touchTarget),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.padded,
                  alignment: Alignment.centerLeft,
                ),
                child: Text(
                  'assistant_market_teaser_cta'.tr(),
                  style: style?.copyWith(
                    color: colors.accentDim,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
