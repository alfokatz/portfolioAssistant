import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/features/genui_core/widgets/catalog_component_scope.dart';
import 'package:portfolio_assistant/shared/widgets/genui_error_card.dart';

/// Envuelve un [widgetBuilder] de catálogo con try/catch y fallback visual,
/// y expone `ctx.type` al subárbol vía [CatalogComponentScope].
Widget guardedCatalogWidget(
  CatalogItemContext ctx,
  Widget Function(CatalogItemContext ctx) builder,
) {
  try {
    return CatalogComponentScope(type: ctx.type, child: builder(ctx));
  } catch (e, stackTrace) {
    debugPrint('GenUI widgetBuilder error: $e');
    debugPrint(stackTrace.toString());
    return const GenUiErrorCard();
  }
}
