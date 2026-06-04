import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:portfolio_assistant/shared/widgets/genui_error_card.dart';

/// Envuelve un [widgetBuilder] de catálogo con try/catch y fallback visual.
Widget guardedCatalogWidget(
  CatalogItemContext ctx,
  Widget Function(CatalogItemContext ctx) builder,
) {
  try {
    return builder(ctx);
  } catch (e, stackTrace) {
    debugPrint('GenUI widgetBuilder error: $e');
    debugPrint(stackTrace.toString());
    return const GenUiErrorCard();
  }
}
