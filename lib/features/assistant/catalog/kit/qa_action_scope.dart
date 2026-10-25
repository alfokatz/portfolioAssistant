import 'package:flutter/widgets.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';

/// Canal entre la card `QaActionProposal` y la pantalla del asistente: en
/// qué quedó cada propuesta y cómo confirmarla, cancelarla o traer el precio
/// de otra fecha. Lo provee la pantalla alrededor de cada surface, como
/// [QaFollowUpScope]; confirmar NO pasa por el modelo (no consume cuota).
///
/// Fuera de la pantalla (tests aislados) no hay scope: la card se ve, pero
/// sus botones quedan deshabilitados.
class QaActionScope extends InheritedWidget {
  const QaActionScope({
    super.key,
    required this.proposals,
    required this.onConfirm,
    required this.onCancel,
    required this.priceOn,
    this.formOf,
    this.onFormChanged,
    this.onOpenPosition,
    this.onOpenClosedPosition,
    this.onOpenAlerts,
    required super.child,
  });

  /// `AssistantState.actionProposals`: cambia de identidad con cada cambio,
  /// y eso es lo que redibuja las cards.
  final Map<String, ActionProposalProgress> proposals;
  final Future<void> Function(ActionDraft draft) onConfirm;

  /// Con lo que había en la card al cancelar (para mostrarlo resuelto).
  final ValueChanged<ActionDraft> onCancel;

  /// Cierre de [ticker] en [date] (o el último hábil antes); `null` si no
  /// se pudo traer.
  final Future<double?> Function(String ticker, DateTime date) priceOn;

  /// Lo que el usuario ya había editado en la card [proposalId], si la card
  /// se desmontó (scroll) y vuelve a montarse; `null` = lo que propuso
  /// Porty.
  final ActionForm? Function(String proposalId)? formOf;

  /// Cada edición de la card. No redibuja nada: solo se guarda para
  /// [formOf].
  final void Function(String proposalId, ActionForm form)? onFormChanged;

  /// "Ver en cartera" después de guardar; sin él, el link no se muestra.
  final ValueChanged<String>? onOpenPosition;

  /// "Ver posición cerrada" después de una venta que cerró todo (ya no hay
  /// nada que ver en cartera); sin él, el link no se muestra.
  final ValueChanged<ClosedPosition>? onOpenClosedPosition;

  /// "Ver mis alertas" después de crear una alerta; sin él, no se muestra.
  final VoidCallback? onOpenAlerts;

  static QaActionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<QaActionScope>();

  ActionProposalProgress progressOf(String proposalId) =>
      proposals[proposalId] ?? ActionProposalProgress.pending;

  @override
  bool updateShouldNotify(QaActionScope oldWidget) =>
      oldWidget.proposals != proposals ||
      (oldWidget.onOpenPosition == null) != (onOpenPosition == null) ||
      (oldWidget.onOpenClosedPosition == null) !=
          (onOpenClosedPosition == null) ||
      (oldWidget.onOpenAlerts == null) != (onOpenAlerts == null);
}
