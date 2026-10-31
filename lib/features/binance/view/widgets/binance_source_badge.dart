import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/features/etoro/view/widgets/etoro_source_badge.dart';
import 'package:portfolio_assistant/features/snaptrade/view/widgets/snaptrade_source_badge.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Marca de origen "Binance": texto (no el logo) sobre el fondo elevado,
/// como la de eToro. [large] para el encabezado de la pantalla.
class BinanceSourceBadge extends StatelessWidget {
  const BinanceSourceBadge({super.key, this.large = false});

  final bool large;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Semantics(
      label: 'binance_badge_semantics'.tr(),
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: large ? 10 : 6,
          vertical: large ? 6 : 2,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        ),
        child: Text(
          'Binance',
          style: (large
                  ? Theme.of(context).textTheme.titleSmall
                  : Theme.of(context).textTheme.labelSmall)
              ?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: large ? null : 9,
                height: 1.1,
              ),
        ),
      ),
    );
  }
}

/// La marca del bróker de donde vino la posición (eToro, Binance u otro
/// bróker conectado por SnapTrade).
class BrokerSourceBadge extends StatelessWidget {
  const BrokerSourceBadge({super.key, required this.source});

  final PositionSource source;

  @override
  Widget build(BuildContext context) =>
      source.isBinance
          ? const BinanceSourceBadge()
          : source.isSnaptrade
          ? const SnaptradeSourceBadge()
          : const EtoroSourceBadge();
}
