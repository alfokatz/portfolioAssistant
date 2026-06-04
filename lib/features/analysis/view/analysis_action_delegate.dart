import 'package:flutter/material.dart';
import 'package:genui/genui.dart';

/// Intercepta eventos de UI del catálogo antes de reenviarlos al modelo.
class AnalysisActionDelegate implements ActionDelegate {
  AnalysisActionDelegate({required this.onInteraction});

  final void Function(String event, Map<String, dynamic> payload) onInteraction;

  static const handledEvents = {
    'portfolio_refresh',
    'asset_detail_open',
    'flow_invest_open',
    'flow_planning_open',
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
