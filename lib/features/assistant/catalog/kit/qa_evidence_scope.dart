import 'package:flutter/widgets.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';

/// Da a las cards del catálogo los datos con los que se armó su surface
/// (las tool calls que tenía el modelo a la vista + la cartera del turno).
///
/// Es lo que permite que una card llene sus números desde los resultados
/// reales de las tools en vez de copiarlos del modelo (ver
/// `QaCompanyAnalysis`). La provee la pantalla del asistente con
/// `OpenAIGenUiService.evidenceFor`; sin scope (tests aislados), vacío.
class QaEvidenceScope extends InheritedWidget {
  const QaEvidenceScope({
    super.key,
    required this.lookup,
    required super.child,
  });

  final TurnEvidence Function(String surfaceId) lookup;

  static TurnEvidence of(BuildContext context, String surfaceId) =>
      context.getInheritedWidgetOfExactType<QaEvidenceScope>()?.lookup(
        surfaceId,
      ) ??
      TurnEvidence.empty;

  @override
  bool updateShouldNotify(QaEvidenceScope oldWidget) =>
      oldWidget.lookup != lookup;
}
