import 'package:flutter/material.dart';
import 'package:genui/genui.dart';

/// Intercepta eventos del catálogo de inversión antes del loop de Conversation.
class InvestmentActionDelegate implements ActionDelegate {
  InvestmentActionDelegate({required this.onInteraction});

  final void Function(String event, Map<String, dynamic> payload) onInteraction;

  static const handledEvents = {
    'risk_profile_updated',
    'investment_confirmed',
    'investment_cancelled',
    'more_options_requested',
    'asset_detail_open',
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
