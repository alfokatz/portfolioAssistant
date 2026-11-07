import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';

/// Da a las cards del catálogo los datos con los que se armó su surface
/// (las tool calls que tenía el modelo a la vista + la cartera del turno).
///
/// Es lo que permite que una card llene sus números desde los resultados
/// reales de las tools en vez de copiarlos del modelo (ver
/// `QaCompanyAnalysis`), y que se redibuje sola cuando llegan datos nuevos
/// (p. ej. las fuentes de Gold recién compradas). La provee la pantalla del
/// asistente con `OpenAIGenUiService.evidenceListenable`; sin scope (tests
/// aislados), vacío.
class QaEvidenceScope extends InheritedWidget {
  const QaEvidenceScope({
    super.key,
    required this.lookup,
    required super.child,
  });

  final ValueListenable<TurnEvidence> Function(String surfaceId) lookup;

  static final _empty = ValueNotifier<TurnEvidence>(TurnEvidence.empty);

  static ValueListenable<TurnEvidence> listenableOf(
    BuildContext context,
    String surfaceId,
  ) =>
      context.getInheritedWidgetOfExactType<QaEvidenceScope>()?.lookup(
        surfaceId,
      ) ??
      _empty;

  static TurnEvidence of(BuildContext context, String surfaceId) =>
      listenableOf(context, surfaceId).value;

  @override
  bool updateShouldNotify(QaEvidenceScope oldWidget) =>
      oldWidget.lookup != lookup;
}
