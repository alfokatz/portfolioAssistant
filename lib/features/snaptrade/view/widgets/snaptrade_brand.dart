import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// El ícono de "otros brókers" (conectados por SnapTrade): un edificio de
/// banco sobre un círculo teñido, como los íconos de Ajustes. No lleva la
/// marca de SnapTrade: para el usuario es su bróker, no el intermediario.
class SnaptradeAppIcon extends StatelessWidget {
  const SnaptradeAppIcon({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colors.chip, shape: BoxShape.circle),
      child: Icon(
        Icons.account_balance_rounded,
        size: size * 0.5,
        color: colors.onChip,
      ),
    );
  }
}

/// La "cara" de los brókers conectados en su pantalla, al lado de Porty: el
/// ícono y "Tu bróker" sobre una card, del alto de [height] (como
/// `BinanceLogoTile`).
class SnaptradeLogoTile extends StatelessWidget {
  const SnaptradeLogoTile({super.key, this.height = 56});

  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.customColors;
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: height * 0.28),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(height * 0.3),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_balance_rounded,
            size: height * 0.38,
            color: colors.textPrimary,
          ),
          SizedBox(width: height * 0.12),
          // Texto traducido (no una marca fija como "Binance"): con tope de
          // ancho para que el lockup entre en pantallas angostas.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: height * 1.4),
            child: Text(
              'snaptrade_tile'.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: height * 0.27,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
