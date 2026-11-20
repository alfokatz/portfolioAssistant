import 'package:portfolio_assistant/features/home_widget/data/widget_items_repository.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_items_selector.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/porty_edge_client.dart';

/// Conteos para los avisos del plan siguiente, por las edge functions v2
/// (spec Am.4.6). Las respuestas son solo números: nunca titulares,
/// tickers ni fechas. Un conteo que falla queda en `null` y el aviso sale
/// sin número.
class EdgeWidgetCountsClient implements WidgetCountsClient {
  EdgeWidgetCountsClient({PortyEdgeClient? client})
    : _client = client ?? PortyEdgeClient();

  /// Tope del servidor por pedido.
  static const maxTickers = 10;

  final PortyEdgeClient _client;

  @override
  Future<WidgetTeaserCounts?> fetch(
    List<String> tickers, {
    DateTime? now,
  }) async {
    final list = tickers.take(maxTickers).toList();
    if (list.isEmpty) return null;
    final joined = list.join(',');
    final responses = await Future.wait([
      _client.get('headlines', query: {'tickers': joined, 'count_only': '1'}),
      _client.get(
        'sec',
        query: {'endpoint': 'earnings_count', 'tickers': joined},
      ),
    ]);
    final news = responses[0];
    final earnings = responses[1];
    int? read(EdgeResponse r, String key) {
      if (!r.ok) return null;
      final value = r.body![key];
      return value is int && value >= 0 ? value : null;
    }

    final counts = WidgetTeaserCounts(
      news48: read(news, 'tickers_48h'),
      news24: read(news, 'tickers_24h'),
      earnings7: read(earnings, 'tickers_7d'),
    );
    if (counts.news48 == null &&
        counts.news24 == null &&
        counts.earnings7 == null) {
      return null;
    }
    return counts;
  }
}
