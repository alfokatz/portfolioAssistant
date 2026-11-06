// EdgeWidgetCountsClient: pide los dos conteos y nunca tira.
// Correr: flutter test test/features/home_widget/data/widget_counts_client_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_counts_client.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/porty_edge_client.dart';

class _FakeEdge extends PortyEdgeClient {
  _FakeEdge(this.responses) : super(baseUrl: 'http://test');

  final Map<String, EdgeResponse> responses;
  final calls = <(String, Map<String, String>)>[];

  @override
  Future<EdgeResponse> get(
    String path, {
    Map<String, String> query = const {},
  }) async {
    calls.add((path, query));
    return responses[path] ?? const EdgeResponse(0, null);
  }
}

void main() {
  test('reads both counts and sends only tickers', () async {
    final edge = _FakeEdge({
      'headlines': const EdgeResponse(200, {
        'tickers_48h': 2,
        'tickers_24h': 1,
        'as_of': '2026-11-05T12:00:00Z',
      }),
      'sec': const EdgeResponse(200, {'tickers_7d': 1}),
    });
    final counts = await EdgeWidgetCountsClient(
      client: edge,
    ).fetch(['AAPL', 'MSFT']);

    expect(counts?.news48, 2);
    expect(counts?.news24, 1);
    expect(counts?.earnings7, 1);
    expect([for (final c in edge.calls) c.$1], ['headlines', 'sec']);
    expect(edge.calls[0].$2, {'tickers': 'AAPL,MSFT', 'count_only': '1'});
    expect(edge.calls[1].$2, {
      'endpoint': 'earnings_count',
      'tickers': 'AAPL,MSFT',
    });
  });

  test('one failing count stays null; the other is kept', () async {
    final edge = _FakeEdge({
      'headlines': const EdgeResponse(403, {
        'error': {'type': 'plan_required'},
      }),
      'sec': const EdgeResponse(200, {'tickers_7d': 3}),
    });
    final counts = await EdgeWidgetCountsClient(client: edge).fetch(['AAPL']);
    expect(counts?.news48, isNull);
    expect(counts?.earnings7, 3);
  });

  test('both failing or no tickers: null', () async {
    final edge = _FakeEdge({});
    expect(await EdgeWidgetCountsClient(client: edge).fetch(['AAPL']), isNull);
    expect(await EdgeWidgetCountsClient(client: edge).fetch(const []), isNull);
  });

  test('caps the request at 10 tickers', () async {
    final edge = _FakeEdge({});
    await EdgeWidgetCountsClient(
      client: edge,
    ).fetch([for (var i = 0; i < 12; i++) 'T$i']);
    expect(edge.calls.first.$2['tickers']!.split(','), hasLength(10));
  });
}
