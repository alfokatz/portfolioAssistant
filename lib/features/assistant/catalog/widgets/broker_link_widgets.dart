import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/features/broker_links/view/open_in_broker_links.dart';
import 'package:portfolio_assistant/features/genui_core/widgets/guarded_catalog_widget.dart';

/// "Abrir en eToro ↗" en el chat. Lo agrega la APP (nunca el modelo, que ni
/// lo ve en el prompt) cuando el usuario quiere vender o borrar algo que
/// vino de un bróker: ver `AssistantAnswerReview._withBrokerLink`. El link
/// no viaja en el JSON: sale de [BrokerLinks] con el ticker y el bróker.
final CatalogItem qaBrokerLinkItem = CatalogItem(
  name: 'QaBrokerLink',
  dataSchema: S.object(
    properties: {
      'ticker': S.string(),
      'broker': S.string(enumValues: ['etoro', 'binance', 'snaptrade']),
    },
    required: ['ticker', 'broker'],
  ),
  widgetBuilder: (ctx) => guardedCatalogWidget(ctx, _qaBrokerLink),
);

Widget _qaBrokerLink(CatalogItemContext ctx) {
  final map = ctx.data as JsonMap;
  final source = switch (map['broker']) {
    'binance' => PositionSource.binance,
    'snaptrade' => PositionSource.snaptrade,
    _ => PositionSource.etoro,
  };
  return Align(
    alignment: Alignment.centerLeft,
    child: OpenInBrokerLinks(
      ticker: '${map['ticker'] ?? ''}'.toUpperCase(),
      sources: {source},
    ),
  );
}
