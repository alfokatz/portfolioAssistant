// SourceCompareFetcher (news-compare, spec 2026-11-20 §3.6): validación del
// cuerpo y errores tipados. Correr: flutter test test/features/assistant/data/web
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/features/assistant/data/web/source_compare_fetcher.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/porty_edge_client.dart';

import '../market/commercial_sources_test.dart' show FakeEdgeClient;

Map<String, Object?> _fixture(String name) =>
    jsonDecode(File('test/fixtures/daily_brief/$name.json').readAsStringSync())
        as Map<String, Object?>;

SourceCompareFetcher _fetcher(EdgeResponse response) =>
    SourceCompareFetcher(client: FakeEdgeClient((_, __) => response));

void main() {
  group('SourceCompareFetcher', () {
    test('ok fixture: points with outlet and https link, as_of kept', () async {
      final r = await _fetcher(
        EdgeResponse(200, _fixture('compare_ok')),
      ).fetch(ticker: 'NVDA');
      expect(r['status'], 'ok');
      final points = r['points']! as List;
      expect(points, hasLength(3));
      final sources = r['sources']! as Map;
      for (final p in points.cast<Map>()) {
        expect(p['source_ids'], isNotEmpty);
        for (final id in p['source_ids'] as List) {
          expect('${(sources[id] as Map)['url']}', startsWith('https://'));
        }
      }
      expect(r['as_of'], isNotNull);
    });

    test('insufficient_sources fixture keeps the outlets, no points', () async {
      final r = await _fetcher(
        EdgeResponse(200, _fixture('compare_insufficient')),
      ).fetch(ticker: 'NVDA');
      expect(r['status'], 'insufficient_sources');
      expect(r['outlets'], ['Reuters']);
      expect(r.containsKey('points'), isFalse);
    });

    test('an agree with a single outlet is demoted to only', () async {
      final body = _fixture('compare_ok');
      (body['points']! as List)[0] = {
        'kind': 'agree',
        'text': 'Reuters dice algo.',
        'source_ids': ['s1', 's1'],
      };
      final r = await _fetcher(EdgeResponse(200, body)).fetch(ticker: 'NVDA');
      expect(((r['points']! as List).first as Map)['kind'], 'only');
    });

    test('points without a usable source are dropped; none left → empty',
        () async {
      final body = _fixture('compare_ok');
      body['sources'] = <String, Object?>{};
      final r = await _fetcher(EdgeResponse(200, body)).fetch(ticker: 'NVDA');
      expect(r['status'], 'empty');
    });

    test('typed errors', () async {
      Future<Map<String, Object?>> run(int code, String type, [Map? extra]) =>
          _fetcher(
            EdgeResponse(code, {
              'error': {'type': type, ...?extra},
            }),
          ).fetch(topicId: 'fed_rates');
      expect(await run(403, 'plan_required', {'required_plan': 'premium'}), {
        'status': 'locked',
        'required_plan': 'premium',
      });
      expect((await run(403, 'plan_required'))['required_plan'], 'gold');
      expect(await run(403, 'disabled'), {
        'status': 'failed',
        'reason': 'disabled',
      });
      expect(await run(429, 'monthly_limit'), {
        'status': 'limit',
        'reason': 'monthly_limit',
      });
      expect((await run(429, 'turn_limit'))['status'], 'limit');
      expect(await run(502, 'upstream_failed'), {'status': 'failed'});
      expect(await run(400, 'invalid_topic'), {'status': 'failed'});
    });

    test('sends exactly one of ticker / topic_id, story_url only if https',
        () async {
      final edge = FakeEdgeClient(
        (_, __) => EdgeResponse(200, _fixture('compare_ok')),
      );
      final f = SourceCompareFetcher(client: edge);
      expect(
        (await f.fetch(ticker: 'NVDA', topicId: 'x'))['reason'],
        'invalid_arguments',
      );
      await f.fetch(topicId: 'fed_rates', storyUrl: 'http://x.com/a', lang: 'en');
      expect(edge.calls.single.path, 'news-compare');
      expect(edge.calls.single.args, {'topic_id': 'fed_rates', 'lang': 'en'});
    });

    test('an ok comparison is cached in the conversation', () async {
      final edge = FakeEdgeClient(
        (_, __) => EdgeResponse(200, _fixture('compare_ok')),
      );
      final f = SourceCompareFetcher(client: edge);
      await f.fetch(ticker: 'NVDA');
      await f.fetch(ticker: 'NVDA');
      expect(edge.calls, hasLength(1));
    });
  });
}
