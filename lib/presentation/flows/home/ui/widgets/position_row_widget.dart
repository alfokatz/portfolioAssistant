import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/position_valuation.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_identity.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';
import 'package:portfolio_assistant/presentation/shared/loading/skeleton.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/skeleton_text.dart';

/// Una posición de la Home, liviana a propósito: logo, ticker y cuántas
/// acciones (el mismo dato en todas las filas); a la derecha, lo que vale
/// hoy y cuánto rinde. La ganancia en dólares y el resto están en el
/// detalle (el chevron dice que se puede tocar). Con [PositionRowWidget.skeleton] es su
/// propio skeleton: mismos paddings y alturas, valores en barras.
class PositionRowWidget extends StatelessWidget {
  final PositionValuation? valuation;
  final VoidCallback? onDetailTap;

  const PositionRowWidget({
    super.key,
    required PositionValuation this.valuation,
    this.onDetailTap,
  });

  const PositionRowWidget.skeleton({super.key})
    : valuation = null,
      onDetailTap = null;

  static const avatarSize = 36.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final valuation = this.valuation;
    const tabular = [FontFeature.tabularFigures()];
    final secondaryStyle = tt.bodySmall?.copyWith(color: colors.textSecondary);

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.cardPadding,
        AppDimens.sp8,
        AppDimens.sp12,
        AppDimens.sp8,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppDimens.touchTarget),
        child: Row(
          children: [
            if (valuation == null)
              const SkeletonBlock(
                width: avatarSize,
                height: avatarSize,
                radius: avatarSize / 2,
              )
            else
              QaTickerAvatar(
                ticker: valuation.position.ticker,
                size: avatarSize,
              ),
            const SizedBox(width: AppDimens.sp12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonText(
                    valuation?.position.ticker,
                    placeholder: 'AAPL',
                    style: tt.titleSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SkeletonText(
                    valuation == null
                        ? null
                        : _shares(valuation.position.quantity),
                    placeholder: '0.00 acciones',
                    style: secondaryStyle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppDimens.sp12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SkeletonText(
                  valuation == null
                      ? null
                      : AppNumberFormat.money(valuation.marketValue),
                  animate: true,
                  placeholder: '\$0,000.00',
                  style: tt.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    fontFeatures: tabular,
                  ),
                ),
                const SizedBox(height: 2),
                SkeletonText(
                  valuation == null
                      ? null
                      : AppNumberFormat.percent(valuation.pnlPercent),
                  animate: true,
                  placeholder: '+00.0%',
                  style: tt.bodySmall?.copyWith(
                    color: colors.pnlColor(valuation?.pnlAbsolute ?? 0),
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabular,
                  ),
                ),
              ],
            ),
            // El chevron es de la fila, no un dato: el skeleton lo lleva
            // igual, así las columnas quedan alineadas con las filas reales.
            if (onDetailTap != null || valuation == null) ...[
              const SizedBox(width: AppDimens.sp4),
              Icon(
                Icons.chevron_right_rounded,
                size: AppDimens.iconMd,
                color: colors.textSecondary,
              ),
            ],
          ],
        ),
      ),
    );

    if (onDetailTap == null) return content;

    return Semantics(
      button: true,
      child: InkWell(
        onTap: () {
          // Haptic y navegación en el mismo frame del tap.
          PortyHapticsService.maybeOf(context)?.selectionTap();
          onDetailTap!();
        },
        child: content,
      ),
    );
  }

  /// "2.04 acciones": en la lista alcanza con 2 decimales (el detalle
  /// muestra la cantidad exacta).
  static String _shares(double quantity) {
    final count = AppNumberFormat.shares(quantity, maxDecimals: 2);
    // Por lo que se ve (1.004 se muestra "1"): nunca "1 acciones".
    return count == '1'
        ? 'position_shares_one'.tr()
        : 'position_shares'.tr(namedArgs: {'count': count});
  }
}
