import 'package:flutter/material.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Contenedor compartido para las tarjetas que Porty genera dentro del
/// catálogo GenUI (`PortfolioQaCatalogWidgets`). Unifica el `Container` +
/// `BoxDecoration` que antes se repetía copiado en cada widget del catálogo.
///
/// [highlighted] marca una tarjeta como insight destacado (tips, alertas,
/// hallazgos importantes): usa `aiCardBorder` (un borde teñido del acento,
/// en vez del borde neutro de una tarjeta de datos común) más el halo
/// bitono frío→cálido que es la firma visual de Porty.
class QaCardShell extends StatelessWidget {
  const QaCardShell({
    super.key,
    required this.child,
    this.highlighted = false,
    this.padding = const EdgeInsets.all(AppDimens.sp12),
    this.margin = const EdgeInsets.symmetric(vertical: AppDimens.sp4),
  });

  final Widget child;
  final bool highlighted;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: PortfolioColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        border: Border.all(
          color:
              highlighted
                  ? PortfolioColors.aiCardBorder
                  : PortfolioColors.border,
        ),
        boxShadow:
            highlighted
                ? [
                  BoxShadow(
                    color: PortfolioColors.accentBlue.withValues(alpha: 0.14),
                    blurRadius: AppDimens.glowBlurMd,
                  ),
                  BoxShadow(
                    color: PortfolioColors.accentWarm.withValues(alpha: 0.10),
                    blurRadius: AppDimens.glowBlurSm,
                  ),
                ]
                : null,
      ),
      child: child,
    );
  }
}
