import 'package:flutter/material.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_plan_scope.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_primitives.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/assistant/services/porty_haptics_service.dart';

/// El único bloque bloqueado de una card: qué incluye Gold acá, con un
/// indicador chico (candado + "Gold") y tocable para abrir el paywall.
///
/// "Premium silencioso": sin banners ni colores de relleno — una fila con el
/// candado en el acento y el texto en el color de rótulo. Una card tiene
/// como máximo UNO: si varias secciones están bloqueadas, se nombran juntas
/// en [title] ("Valuación, resultados y noticias").
///
/// Al tocar: estado presionado + haptic de selección en el mismo frame
/// (antes de que la hoja termine de abrirse), después [QaPlanScope].
class QaGoldLock extends StatefulWidget {
  const QaGoldLock({
    super.key,
    required this.title,
    required this.request,
    this.caption,
  });

  /// Qué se desbloquea ("Noticias", "Valuación, resultados y noticias").
  final String title;

  /// Línea opcional debajo (p. ej. "1 análisis Gold gratis esta semana").
  final String? caption;
  final QaPaywallRequest request;

  @override
  State<QaGoldLock> createState() => _QaGoldLockState();
}

class _QaGoldLockState extends State<QaGoldLock> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scope = QaPlanScope.maybeOf(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 16,
            color: QaColors.accentBlue,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: QaText.bodyStrong.copyWith(fontSize: 13.5),
                ),
                Text(
                  widget.caption ?? 'Incluido en el plan Gold',
                  style: QaText.label,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const QaTag('Gold', icon: Icons.lock_outline_rounded),
        ],
      ),
    );
    if (scope == null) return row;
    return Semantics(
      button: true,
      label: 'Desbloquear con Gold: ${widget.title}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          _setPressed(true);
          PortyHapticsService.maybeOf(context)?.lockedTap();
        },
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: () => scope.openPaywall(widget.request),
        child: AnimatedOpacity(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 120),
          opacity: _pressed ? 0.6 : 1,
          child: row,
        ),
      ),
    );
  }
}
