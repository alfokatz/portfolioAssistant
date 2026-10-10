import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/catalog/widgets/reveal_step.dart';
import 'package:portfolio_assistant/presentation/base/theme/app_dimens.dart';

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
/// turno y entra recién cuando le toca, con la entrada común a todas
/// ([RevealEntrance]: abre su espacio + fade + slide, y su haptic). Fuera
/// de una surface (p. ej. un test aislado) se muestra directo.
class QaCardShell extends StatelessWidget {
  const QaCardShell({
    super.key,
    required Widget child,
    this.highlighted = false,
    this.padding = const EdgeInsets.all(QaSpace.cardPadding),
    this.margin = const EdgeInsets.symmetric(vertical: AppDimens.sp6),
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
    this.padding = const EdgeInsets.all(QaSpace.cardPadding),
    this.margin = const EdgeInsets.symmetric(vertical: AppDimens.sp6),
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
      width: double.infinity,
      margin: margin,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: QaColors.surfaceCard,
        borderRadius: BorderRadius.circular(QaSpace.cardRadius),
        border: Border.all(
          color: highlighted ? QaColors.aiCardBorder : QaColors.border,
        ),
        boxShadow:
            highlighted
                ? [
                  BoxShadow(
                    color: QaColors.accentBlue.withValues(alpha: 0.14),
                    blurRadius: AppDimens.glowBlurMd,
                  ),
                  BoxShadow(
                    color: QaColors.accentWarm.withValues(alpha: 0.10),
                    blurRadius: AppDimens.glowBlurSm,
                  ),
                ]
                // Sombra casi imperceptible: despega la card del fondo
                // cálido sin el look "material elevado".
                : const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 12,
                    offset: Offset(0, 2),
                  ),
                ],
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
      return RevealStep.entrance(
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
