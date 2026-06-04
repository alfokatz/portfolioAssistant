import 'package:flutter/material.dart';
import 'package:genui/genui.dart';

/// Intercepta eventos del catálogo de planificación antes del loop de Conversation.
class PlanningActionDelegate implements ActionDelegate {
  PlanningActionDelegate({required this.onInteraction});

  final void Function(String event, Map<String, dynamic> payload) onInteraction;

  static const handledEvents = {
    'goal_updated',
    'contribution_updated',
    'scenario_selected',
    'flow_invest_open',
    'recalculate_requested',
  };

  @override
  bool handleEvent(
    BuildContext context,
    UiEvent event,
    SurfaceContext genUiContext,
    Widget Function(
      SurfaceDefinition,
      Catalog,
      String,
      DataContext,
    )
    buildWidget,
  ) {
    if (event is! UserActionEvent) return false;
    if (!handledEvents.contains(event.name)) return false;
    onInteraction(event.name, Map<String, dynamic>.from(event.context));
    return true;
  }
}
