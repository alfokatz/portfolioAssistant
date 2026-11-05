import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_images.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Gris casi negro de Binance: el fondo de su ícono (igual en claro y en
/// oscuro, como el de eToro).
const _binanceInk = Color(0xFF1E2026);

/// El ícono de Binance como el de su app: los rombos amarillos sobre un
/// círculo oscuro. Va donde la app pone un ícono en círculo (Ajustes).
class BinanceAppIcon extends StatelessWidget {
  const BinanceAppIcon({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: const BoxDecoration(color: _binanceInk, shape: BoxShape.circle),
    child: AppImages.binanceMark(size: size * 0.56),
  );
}

/// La "cara" de Binance en sus pantallas, al lado de Porty: el símbolo y el
/// nombre sobre una card, del alto de [height] (como `EtoroLogoTile`).
class BinanceLogoTile extends StatelessWidget {
  const BinanceLogoTile({super.key, this.height = 56});

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
          AppImages.binanceMark(size: height * 0.38),
          SizedBox(width: height * 0.12),
          Text(
            'Binance',
            style: TextStyle(
              fontSize: height * 0.27,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
