import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/reveal_step.dart';
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
///
/// Todo widget que use este shell queda con reveal secuencial "gratis": si
/// hay una [SurfaceRevealScope] ancestro (la respuesta de Porty siempre la
/// provee — ver `PortfolioQaAssistantSurface`), la card reclama el próximo
/// turno y aparece recién cuando le toca, en vez de saltar junto con todo lo
/// demás. Fuera de una surface (p. ej. un test aislado) se muestra directo.
class QaCardShell extends StatelessWidget {
  const QaCardShell({
    super.key,
    required Widget child,
    this.highlighted = false,
    this.padding = const EdgeInsets.all(AppDimens.sp12),
    this.margin = const EdgeInsets.symmetric(vertical: AppDimens.sp4),
  }) : child = child,
       staged = null;

  /// Variante para cards que quieren su propio reveal interno en etapas
  /// ("título antes que valores", dibujo de un chart, etc.) en vez del
  /// fade-in genérico de una sola pieza. [staged] recibe exactamente el
  /// mismo contrato que el `builder` de [RevealStep] — `active` (si ya le
  /// tocó el turno a esta card) y `onFinished` (llamarlo cuando termine SU
  /// PROPIO reveal interno, para recién ahí desbloquear la siguiente card).
  const QaCardShell.staged({
    super.key,
    required Widget Function(BuildContext, bool active, VoidCallback onFinished)
    staged,
    this.highlighted = false,
    this.padding = const EdgeInsets.all(AppDimens.sp12),
    this.margin = const EdgeInsets.symmetric(vertical: AppDimens.sp4),
  }) : child = null,
       staged = staged;

  final Widget? child;
  final Widget Function(BuildContext, bool active, VoidCallback onFinished)?
  staged;
  final bool highlighted;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  Widget _decorate(Widget inner) {
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
      child: inner,
    );
  }

  @override
  Widget build(BuildContext context) {
    final revealController = SurfaceRevealScope.maybeOf(context);
    final staged = this.staged;

    if (staged != null) {
      if (revealController == null) {
        return _decorate(staged(context, true, () {}));
      }
      return RevealStep(
        controller: revealController,
        builder:
            (context, active, onFinished) =>
                _decorate(staged(context, active, onFinished)),
      );
    }

    final card = _decorate(child!);
    if (revealController == null) return card;
    return RevealStep.fade(controller: revealController, child: card);
  }
}
