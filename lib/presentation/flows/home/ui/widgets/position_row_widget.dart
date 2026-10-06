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

/// Una posición de la Home: logo, ticker, cuántas acciones y cuánto pesa en
/// la cartera; a la derecha, lo que vale hoy y lo que ganó o perdió desde la
/// compra. Con [PositionRowWidget.skeleton] es su propio skeleton: mismos
/// paddings y alturas, valores en barras.
///
/// Sin mini gráfico: el que había era una recta entre el precio de compra y
/// el actual (no una serie real), y sugería una evolución que no existía.
class PositionRowWidget extends StatelessWidget {
  final PositionValuation? valuation;

  /// Valor de toda la cartera, para el peso de la posición. Sin él, la fila
  /// muestra solo las acciones.
  final double? portfolioValue;
  final VoidCallback? onDetailTap;

  const PositionRowWidget({
    super.key,
    required PositionValuation this.valuation,
    this.portfolioValue,
    this.onDetailTap,
  });

  const PositionRowWidget.skeleton({super.key})
    : valuation = null,
      portfolioValue = null,
      onDetailTap = null;

  static const avatarSize = 36.0;

  /// "2.0434" en vez de "2.0434492300000002": hasta 4 decimales, sin ceros
  /// de más.
  static final _shares = NumberFormat('#,##0.####');

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    final tt = Theme.of(context).textTheme;
    final valuation = this.valuation;
    const tabular = [FontFeature.tabularFigures()];

    String? shares;
    String? weight;
    String? pnl;
    if (valuation != null) {
      final quantity = valuation.position.quantity;
      shares =
          quantity == 1
              ? 'position_shares_one'.tr()
              : 'position_shares'.tr(
                namedArgs: {'count': _shares.format(quantity)},
              );
      final total = portfolioValue;
      if (total != null && total > 0) {
        weight = AppNumberFormat.percent(
          valuation.marketValue / total * 100,
          signed: false,
        );
      }
      pnl =
          '${AppNumberFormat.signedMoney(valuation.pnlAbsolute)} · '
          '${AppNumberFormat.percent(valuation.pnlPercent)}';
    }

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.cardPadding,
        vertical: AppDimens.sp8,
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
                  // El peso al lado del ticker, como en la leyenda de la
                  // cartera de Porty ("NVDA 38.2%").
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
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
                      if (weight != null) ...[
                        const SizedBox(width: AppDimens.sp6),
                        Semantics(
                          label: 'home_position_weight'.tr(
                            namedArgs: {'pct': weight},
                          ),
                          excludeSemantics: true,
                          child: Text(
                            weight,
                            style: tt.bodySmall?.copyWith(
                              color: colors.textSecondary,
                              fontFeatures: tabular,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  SkeletonText(
                    shares,
                    placeholder: '00 acciones',
                    style: tt.bodySmall?.copyWith(color: colors.textSecondary),
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
                  pnl,
                  animate: true,
                  placeholder: '+\$000.00 · +0.0%',
                  style: tt.bodySmall?.copyWith(
                    color: colors.pnlColor(valuation?.pnlAbsolute ?? 0),
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabular,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (onDetailTap == null) return content;

    return InkWell(
      onTap: () {
        // Haptic y navegación en el mismo frame del tap.
        PortyHapticsService.maybeOf(context)?.selectionTap();
        onDetailTap!();
      },
      child: content,
    );
  }
}
